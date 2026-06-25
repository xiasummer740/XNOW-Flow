#!/usr/bin/env python3
"""
vps-inject.py — 在 Linux VPS 上将 xnower.dylib 注入 TikTok IPA
用法: python3 vps-inject.py <IPA路径> <dylib路径> [输出IPA路径]

原理: 纯 Python 操作 Mach-O 二进制，无需 macOS 工具链
"""

import struct, os, sys, shutil, tempfile, zipfile, plistlib, json

MAGIC_FAT = 0xcafebabe
MAGIC_FAT_LE = 0xbebafeca
MAGIC_MH_MAGIC_64 = 0xfeedfacf
LC_LOAD_DYLIB = 0x0C
LC_SEGMENT_64 = 0x19

def align(x, a):
    return (x + a - 1) & ~(a - 1)

def inject_dylib_to_macho(data, dylib_path_bytes):
    """向 Mach-O 二进制添加 LC_LOAD_DYLIB 加载命令"""
    if len(data) < 4:
        return None, "File too small"

    magic = struct.unpack_from("<I", data, 0)[0]

    # Handle FAT binaries
    if magic in (MAGIC_FAT, MAGIC_FAT_LE):
        narch = struct.unpack_from("<I", data, 4)[0]
        if magic == MAGIC_FAT:  # big endian
            narch = struct.unpack_from(">I", data, 4)[0]

        offset = 8
        for i in range(narch):
            if magic == MAGIC_FAT:
                cpu_type, cpu_sub, off, size, align_val = struct.unpack_from(">IIIII", data, offset)
            else:
                cpu_type, cpu_sub, off, size, align_val = struct.unpack_from("<IIIII", data, offset)

            # Process arm64 slices (CPU_TYPE_ARM64 = 0x0100000c, CPU_TYPE_ARM64_32 = 0x0200000c)
            if cpu_type == 0x0100000c:  # ARM64
                slice_data = data[off:off+size]
                result, err = inject_single_arch(slice_data, dylib_path_bytes)
                if err:
                    return None, f"arm64 slice: {err}"
                data = data[:off] + result + data[off+size:]
            offset += 20

        return data, None

    # Single arch
    if magic == MAGIC_MH_MAGIC_64:
        result, err = inject_single_arch(data, dylib_path_bytes)
        if err:
            return None, err
        return result, None

    return None, f"Unknown Mach-O magic: 0x{magic:08x}"

def inject_single_arch(data, dylib_path_bytes):
    """向单个架构的 Mach-O 添加 LC_LOAD_DYLIB"""
    if len(data) < 8:
        return None, "Data too small"

    # Parse Mach-O header (64-bit)
    # struct mach_header_64: magic(4) + cputype(4) + cpusubtype(4) + filetype(4) +
    #                       ncmds(4) + sizeofcmds(4) + flags(4) + reserved(4) = 32
    ncmds = struct.unpack_from("<I", data, 16)[0]
    sizeofcmds = struct.unpack_from("<I", data, 20)[0]

    # Check if already has our dylib
    cmd_offset = 32
    for i in range(ncmds):
        if cmd_offset + 8 > len(data):
            break
        cmd_type, cmd_size = struct.unpack_from("<II", data, cmd_offset)
        if cmd_type == LC_LOAD_DYLIB and cmd_offset + 24 <= len(data):
            # Read dylib path
            name_offset = cmd_offset + 24
            path_end = data.find(b'\x00', name_offset, cmd_offset + cmd_size)
            if path_end > name_offset:
                name = data[name_offset:path_end]
                if b'xnower.dylib' in name:
                    return data, None  # Already injected, skip
        cmd_offset += cmd_size

    # Build LC_LOAD_DYLIB command
    name_padded = dylib_path_bytes + b'\x00'
    name_padded_len = len(name_padded)
    name_offset = 24  # Offset from start of LC_LOAD_DYLIB to path
    cmd_size = align(24 + name_padded_len, 8)

    cmd = bytearray(cmd_size)
    struct.pack_into("<II", cmd, 0, LC_LOAD_DYLIB, cmd_size)
    # struct dylib: name_offset, timestamp=0, current_version=0, compat_version=0
    struct.pack_into("<IIII", cmd, 8, name_offset, 0, 0, 0)
    cmd[24:24+len(name_padded)] = name_padded

    # Insert the command
    new_data = bytearray(len(data) + cmd_size)

    # Check for __LINKEDIT - insert before it if we can, otherwise append
    linkedit_offset = -1
    cmd_offset2 = 32
    for i in range(ncmds):
        if cmd_offset2 + 8 > len(data):
            break
        cmd_type2, _ = struct.unpack_from("<II", data, cmd_offset2)
        if cmd_type2 == LC_SEGMENT_64:
            segname = data[cmd_offset2+8:cmd_offset2+24].rstrip(b'\x00')
            if segname == b'__LINKEDIT':
                linkedit_offset = cmd_offset2
                break
        cmd_offset2 += struct.unpack_from("<I", data, cmd_offset2 + 4)[0]

    if linkedit_offset > 0:
        # Insert before __LINKEDIT
        insert_point = linkedit_offset
        new_data[:insert_point] = data[:insert_point]
        new_data[insert_point:insert_point+cmd_size] = cmd
        new_data[insert_point+cmd_size:] = data[insert_point:]
    else:
        # Append at end of commands
        insert_point = 32 + sizeofcmds
        new_data[:insert_point] = data[:insert_point]
        new_data[insert_point:insert_point+cmd_size] = cmd
        new_data[insert_point+cmd_size:] = data[insert_point:]

    # Update header
    struct.pack_into("<I", new_data, 16, ncmds + 1)
    struct.pack_into("<I", new_data, 20, sizeofcmds + cmd_size)

    return bytes(new_data), None

def find_app_binary(extracted_path):
    """Find the main Mach-O binary in the extracted IPA"""
    payload = os.path.join(extracted_path, "Payload")
    if not os.path.isdir(payload):
        return None

    for item in os.listdir(payload):
        if item.endswith(".app"):
            app_dir = os.path.join(payload, item)
            # The binary has the same name as the .app without extension
            binary_name = item[:-4]  # Remove .app
            binary_path = os.path.join(app_dir, binary_name)
            if os.path.isfile(binary_path):
                return binary_path, app_dir

    # Fallback: find any Mach-O file
    for root, dirs, files in os.walk(payload):
        for f in files:
            fp = os.path.join(root, f)
            with open(fp, "rb") as fh:
                magic = struct.unpack_from("<I", fh.read(4), 0)[0]
                if magic in (MAGIC_FAT, MAGIC_FAT_LE, MAGIC_MH_MAGIC_64):
                    return fp, os.path.dirname(fp)
    return None

def inject_ipa(ipa_path, dylib_path, output_path):
    """Main injection function"""
    tmpdir = tempfile.mkdtemp()
    try:
        print(f"[1/5] 解压 IPA ...")
        with zipfile.ZipFile(ipa_path, 'r') as z:
            z.extractall(tmpdir)

        # Find binary
        result = find_app_binary(tmpdir)
        if not result:
            print("ERROR: 未找到主二进制")
            return False

        binary_path, app_dir = result
        binary_name = os.path.basename(binary_path)
        print(f"  主二进制: {binary_name}")
        print(f"  App路径: {app_dir}")

        # Copy dylib to Frameworks
        print(f"\n[2/5] 复制 dylib 到 Frameworks ...")
        frameworks_dir = os.path.join(app_dir, "Frameworks")
        os.makedirs(frameworks_dir, exist_ok=True)
        target_dylib = os.path.join(frameworks_dir, "xnower.dylib")
        shutil.copy2(dylib_path, target_dylib)
        os.chmod(target_dylib, 0o755)
        print(f"  Copied to Frameworks/xnower.dylib")

        # Also copy config
        config_src = os.path.join(os.path.dirname(dylib_path), "Config.plist")
        if os.path.exists(config_src):
            shutil.copy2(config_src, os.path.join(app_dir, "xnower-config.plist"))
            print(f"  Config.plist embedded")

        # Inject dylib load command
        print(f"\n[3/5] 注入 LC_LOAD_DYLIB ...")
        with open(binary_path, "rb") as f:
            binary_data = f.read()

        dylib_ref = b"@executable_path/Frameworks/xnower.dylib\x00"

        if b"xnower.dylib" in binary_data:
            print(f"  已存在，跳过注入")
        else:
            new_data, err = inject_dylib_to_macho(binary_data, dylib_ref)
            if err:
                print(f"  ERROR: {err}")
                return False
            if new_data:
                # Backup original
                bak_path = binary_path + ".bak"
                shutil.copy2(binary_path, bak_path)
                with open(binary_path, "wb") as f:
                    f.write(new_data)
                print(f"  [OK] LC_LOAD_DYLIB 注入成功")
            else:
                print(f"  Skipped (already injected or no change)")

        # Copy Config.plist to output dir
        print(f"\n[4/5] 打包新 IPA ...")
        output_dir = os.path.dirname(output_path) or "."
        os.makedirs(output_dir, exist_ok=True)

        # Remove old IPA if exists
        if os.path.exists(output_path):
            os.remove(output_path)

        # Create new IPA
        with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=5) as zout:
            for root, dirs, files in os.walk(tmpdir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, tmpdir)
                    zout.write(file_path, arcname)

        print(f"\n[5/5] 完成!")
        out_size = os.path.getsize(output_path)
        print(f"  输出: {output_path}")
        print(f"  大小: {out_size/1024/1024:.1f} MB")

        # Verify
        print(f"\n  验证注入:")
        with zipfile.ZipFile(output_path, 'r') as z:
            names = z.namelist()
            dylib_in_ipa = [n for n in names if 'xnower' in n.lower()]
            if dylib_in_ipa:
                for n in dylib_in_ipa:
                    info = z.getinfo(n)
                    print(f"    [OK] {n} ({info.file_size/1024:.0f} KB)")
            else:
                print(f"    [ERR] xnower.dylib 未在 IPA 中找到!")

        return True

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 vps-inject.py <input.ipa> <xnower.dylib> [output.ipa]")
        sys.exit(1)

    ipa_path = sys.argv[1]
    dylib_path = sys.argv[2]
    output_path = sys.argv[3] if len(sys.argv) > 3 else ipa_path.replace(".ipa", "_XNOW.ipa")

    if not os.path.exists(ipa_path):
        print(f"ERROR: IPA not found: {ipa_path}")
        sys.exit(1)
    if not os.path.exists(dylib_path):
        print(f"ERROR: dylib not found: {dylib_path}")
        sys.exit(1)

    success = inject_ipa(ipa_path, dylib_path, output_path)
    sys.exit(0 if success else 1)
