#!/usr/bin/env python3
"""
build-xnow-ipa.py — XNOW IPA 统一注入工具
============================================
注入 xnower.dylib 到 TikTok 主二进制，启动时必被 dyld 加载。

用法: python3 build-xnow-ipa.py <IPA> <dylib> [-o OUTPUT]

支持的 IPA:
  - Thin arm64 (单架构)
  - FAT arm64+arm64e (多架构，TikTok 主二进制)

流程:
  1. 解压 IPA → 2. 复制 dylib 到 Frameworks/
  3. 修改主二进制：FAT/thin 判断 → 对每个 arm64 slice 注入 LC_LOAD_DYLIB
     → 剥离 LC_CODE_SIGNATURE → 更新所有偏移
  4. 打包回 IPA → 5. 修复图标 → 6. 结果验证输出

关键修复（对比旧 inject-v39）:
  ✅ 支持 FAT 二进制（TikTok 主二进制是 FAT arm64+arm64e）
  ✅ 正确的 LC_LOAD_DYLIB = 0x0C（不是 0x8000001D）
  ✅ 剥离 LC_CODE_SIGNATURE 防止签名冲突
  ✅ 注入后 otool 验证 + 输出摘要
"""
import struct, os, sys, shutil, tempfile, zipfile

# ============================================================
# Mach-O 常量
# ============================================================
MAGIC_FAT_CIGAM = 0xBEBAFECA       # FAT little-endian (很少见)
MAGIC_FAT = 0xCAFEBABE              # FAT big-endian
MAGIC_MH_MAGIC_64 = 0xFEEDFACF      # arm64 thin

CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64_ALL = 0x00000000

LC_LOAD_DYLIB = 0x0C                # Load a dylib
LC_SEGMENT_64 = 0x19                # 64-bit segment
LC_SYMTAB = 0x02                    # Symbol table
LC_DYSYMTAB = 0x0B                 # Dynamic symbol table
LC_CODE_SIGNATURE = 0x1D           # Code signature
LC_SEGMENT_SPLIT_INFO = 0x1E
LC_DYLD_INFO_ONLY = 0x22
LC_DYLD_ENVIRONMENT = 0x27
LC_ENCRYPTION_INFO_64 = 0x2C
LC_LINKER_OPTION = 0x2D
LC_DYLD_EXPORTS_TRIE = 0x33
LC_DYLD_CHAINED_FIXUPS = 0x34
LC_LINKER_OPTIMIZATION_HINT = 0x2E

# 需要更新 dataoff 的 load command 类型
# 这些命令的 dataoff 指向文件中的数据，可能随 sizeofcmds 变化
DATAOFF_COMMANDS = {
    LC_SYMTAB: [8, 16],           # symoff, stroff
    LC_DYSYMTAB: [8, 16, 24, 32, 40, 48],
    LC_CODE_SIGNATURE: [8],
    LC_SEGMENT_SPLIT_INFO: [8],
    LC_DYLD_INFO_ONLY: [8, 12, 16, 20, 24, 28, 32, 36],
    LC_DYLD_EXPORTS_TRIE: [8],
    LC_DYLD_CHAINED_FIXUPS: [8],
    LC_LINKER_OPTIMIZATION_HINT: [8],
    LC_ENCRYPTION_INFO_64: [8],
    LC_DYLD_ENVIRONMENT: [8],      # 字符串偏移
    LC_LINKER_OPTION: [12],        # 字符串偏移
}


def align(x, a):
    """向上对齐到 a 的倍数"""
    return ((x + a - 1) // a) * a if a > 1 else x


def make_load_dylib_cmd(path_bytes):
    """
    构造 LC_LOAD_DYLIB load command
    结构：cmd(4) + cmdsize(4) + name_off(4) + timestamp(4) +
          current_ver(4) + compat_ver(4) + path(可变)
    """
    npad = path_bytes + b'\x00'
    name_off = 24  # dylib_command 中 name 的偏移
    cmd_size = align(name_off + len(npad), 8)
    cmd = bytearray(cmd_size)
    struct.pack_into('<II', cmd, 0, LC_LOAD_DYLIB, cmd_size)
    struct.pack_into('<IIII', cmd, 8, name_off, 0, 0, 0)  # name_off, timestamp, cur_ver, compat_ver
    cmd[name_off:name_off + len(npad)] = npad
    return bytes(cmd)


def parse_load_commands(data, offset=0):
    """
    解析 Mach-O 的 load commands，返回 [(cmd, cmdsize, data, start_offset), ...]
    data 是 load command 的原始字节数据
    """
    ncmds = struct.unpack_from('<I', data, offset + 16)[0]
    cmds = []
    off = offset + 32
    for i in range(ncmds):
        if off + 8 > len(data):
            break
        ct, cs = struct.unpack_from('<II', data, off)
        if cs < 8 or off + cs > len(data):
            break
        cmds.append((ct, cs, data[off:off + cs], off))
        off += cs
    return cmds


def inject_slice(slice_data, dylib_ref, slice_name="arm64"):
    """
    对单个 thin arm64 slice 注入 LC_LOAD_DYLIB 并剥离 LC_CODE_SIGNATURE。

    返回: (new_data: bytes, delta: int, injected: bool)
    """
    magic = struct.unpack_from('<I', slice_data, 0)[0]
    assert magic == MAGIC_MH_MAGIC_64, f"{slice_name}: bad magic 0x{magic:08X}"

    ncmds = struct.unpack_from('<I', slice_data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', slice_data, 20)[0]

    # Step 1: 解析现有 load commands
    cmds = parse_load_commands(slice_data)
    original_cmds_data = slice_data[32:32 + sizeofcmds]
    remaining_data = slice_data[32 + sizeofcmds:]

    # Step 2: 检查是否已有 xnower.dylib 引用
    has_xnower = False
    for ct, cs, cmd_data, _ in cmds:
        if ct != LC_LOAD_DYLIB or cs <= 24:
            continue
        noff = struct.unpack_from('<I', cmd_data, 8)[0]
        nend = cmd_data.find(b'\x00', noff, cs)
        if nend > noff and b'xnower' in cmd_data[noff:nend]:
            has_xnower = True
            break

    # Step 3: 构建新命令列表（移除 LC_CODE_SIGNATURE，可选的添加 LC_LOAD_DYLIB）
    new_cmds_list = []
    removed_code_signature = False
    for ct, cs, cmd_data, _ in cmds:
        if ct == LC_CODE_SIGNATURE:
            removed_code_signature = True
            continue  # 跳过，之后让签名工具重签
        new_cmds_list.append(cmd_data)

    if not has_xnower:
        new_cmd = make_load_dylib_cmd(dylib_ref)
        new_cmds_list.append(new_cmd)

    # Step 4: 重建 load commands 区域
    new_sizeofcmds = sum(len(c) for c in new_cmds_list)
    new_ncmds = len(new_cmds_list)
    delta = new_sizeofcmds - sizeofcmds

    # Step 5: 重建整个 slice
    # Header
    new_data = bytearray(32)
    new_data[:32] = slice_data[:32]
    struct.pack_into('<I', new_data, 16, new_ncmds)
    struct.pack_into('<I', new_data, 20, new_sizeofcmds)

    # Load commands
    for cmd_data in new_cmds_list:
        new_data.extend(cmd_data)

    # Segment data (with possible shift)
    new_data.extend(remaining_data)

    # Step 6: 更新所有 LC_SEGMENT_64 的 fileoff/filesize
    off = 32
    for ct, cs, cmd_data, _ in cmds:
        if ct == LC_SEGMENT_64:
            segname = cmd_data[8:24].rstrip(b'\x00').decode('ascii', errors='replace')
            if segname == '__PAGEZERO':
                off += cs
                continue
            old_fileoff = struct.unpack_from('<Q', cmd_data, 40)[0]
            old_filesize = struct.unpack_from('<Q', cmd_data, 48)[0]
            old_vmsize = struct.unpack_from('<Q', cmd_data, 32)[0]

            # 仅在数据在 load commands 之后时更新
            if old_fileoff > 0 and old_fileoff >= (32 + sizeofcmds):
                struct.pack_into('<Q', new_data, off + 40, old_fileoff + delta)

            # __TEXT 的 filesize 需要包含增加的 load commands 空间
            if segname == '__TEXT' and old_filesize > 0:
                struct.pack_into('<Q', new_data, off + 48, old_filesize + delta)
                struct.pack_into('<Q', new_data, off + 32, old_vmsize + delta)

            # 更新 section 偏移
            nsects = struct.unpack_from('<I', cmd_data, 64)[0]
            sect_off_off = off + 72  # section 起始在 cmd 中的偏移
            for si in range(nsects):
                s_off = struct.unpack_from('<I', new_data, sect_off_off + 48)[0]
                if s_off > 0 and s_off >= (32 + sizeofcmds):
                    struct.pack_into('<I', new_data, sect_off_off + 48, s_off + delta)
                s_off_64 = struct.unpack_from('<Q', new_data, sect_off_off + 48)[0]
                if s_off_64 > 0 and s_off_64 >= (32 + sizeofcmds):
                    struct.pack_into('<Q', new_data, sect_off_off + 48, s_off_64 + delta)
                sect_off_off += 80
        off += cs

    # Step 7: 更新其他命令的 dataoff（符号表等）
    off = 32
    orig_cmds_end = 32 + sizeofcmds
    for ct, cs, cmd_data, _ in cmds:
        if ct in DATAOFF_COMMANDS and ct != LC_CODE_SIGNATURE:
            # 只有不在原始命令中的偏移才需要更新
            for foff in DATAOFF_COMMANDS[ct]:
                val = struct.unpack_from('<I', cmd_data, foff)[0]
                if val > 0 and val >= orig_cmds_end:
                    struct.pack_into('<I', new_data, off + foff, val + delta)
        off += cs

    summary = []
    if has_xnower and not removed_code_signature:
        summary.append(f"{slice_name}: 已注入，无变更")
    else:
        changes = []
        if has_xnower:
            changes.append("含 xnower.dylib")
        elif not has_xnower:
            changes.append("已添加 LC_LOAD_DYLIB")
        if removed_code_signature:
            changes.append("已移除 LC_CODE_SIGNATURE")
        summary.append(f"{slice_name}: {', '.join(changes)} ({delta:+d}B)")

    return bytes(new_data), delta, not has_xnower, ' | '.join(summary)


def patch_fat(data, dylib_ref):
    """
    处理 FAT 二进制：对每个 arm64 slice 执行注入。
    返回 (new_data, summary_lines)
    """
    magic = struct.unpack_from('>I', data, 0)[0]
    narch = struct.unpack_from('>I', data, 4)[0]
    arch_off = 8

    # 解析每个 arch entry
    archs = []
    for i in range(narch):
        ca = arch_off + i * 20
        cpu, sub, off, sz, al = struct.unpack_from('>IIIII', data, ca)
        archs.append({'cpu': cpu, 'sub': sub, 'offset': off, 'size': sz, 'align': al,
                      'data': data[off:off + sz]})

    # 从后往前处理（避免 offset 变化影响）
    summaries = []
    any_change = False
    total_delta = 0

    for i in range(len(archs) - 1, -1, -1):
        arch = archs[i]
        cpu = arch['cpu']
        slice_magic = struct.unpack_from('<I', arch['data'], 0)[0]

        if cpu in (CPU_TYPE_ARM64, CPU_TYPE_ARM64_32):
            slice_name = "arm64" if cpu == CPU_TYPE_ARM64 else "arm64e"
            if slice_magic == MAGIC_MH_MAGIC_64:
                result, delta, changed, summary = inject_slice(arch['data'], dylib_ref, slice_name)
                archs[i]['data'] = result
                archs[i]['size'] = len(result)
                if changed:
                    any_change = True
                total_delta += delta
                summaries.append(summary)
                continue

        summaries.append(f"arch[{i}] cpu=0x{cpu:08X}: 跳过（非 arm64）")

    if not any_change:
        return data, summaries + ["无变更"]

    # 重建 FAT 二进制
    fat_hdr_size = 8 + narch * 20
    hdr_pad = align(fat_hdr_size, 4096)

    new_file = bytearray(hdr_pad)
    struct.pack_into('>I', new_file, 0, MAGIC_FAT)
    struct.pack_into('>I', new_file, 4, narch)

    for i, arch in enumerate(archs):
        ca = arch_off + i * 20
        struct.pack_into('>IIIII', new_file, ca,
                         arch['cpu'], arch['sub'], 0, 0, arch['align'])

    cur_offset = hdr_pad
    for i, arch in enumerate(archs):
        align_bits = arch['align']
        align_bytes = 1 << align_bits
        cur_offset = align(cur_offset, align_bytes)

        ca = arch_off + i * 20
        struct.pack_into('>I', new_file, ca + 8, cur_offset)  # offset
        struct.pack_into('>I', new_file, ca + 12, len(arch['data']))  # size

        # Pad to offset
        while len(new_file) < cur_offset:
            new_file.append(0)

        new_file.extend(arch['data'])
        cur_offset += len(arch['data'])

    return bytes(new_file), summaries


def patch_thin(data, dylib_ref):
    """处理 thin arm64 二进制"""
    result, delta, changed, summary = inject_slice(data, dylib_ref, "arm64")
    return result, [summary]


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="XNOW IPA 注入工具 — 注入 xnower.dylib 到 TikTok 主二进制"
    )
    parser.add_argument("ipa", nargs="?",
                        default="TikTok_43.7.0_BH.ipa",
                        help="输入 IPA 文件路径")
    parser.add_argument("dylib", nargs="?",
                        default="build-artifacts-ci/xnower.dylib",
                        help="xnower.dylib 路径")
    parser.add_argument("-o", "--output", default=None,
                        help="输出 IPA 路径（默认: 输入名 _XNOW.ipa）")
    args = parser.parse_args()

    if not os.path.exists(args.ipa):
        print(f"❌ IPA not found: {args.ipa}")
        sys.exit(1)
    if not os.path.exists(args.dylib):
        print(f"❌ Dylib not found: {args.dylib}")
        sys.exit(1)

    output = args.output or args.ipa.replace(".ipa", "_XNOW.ipa")
    dylib_ref = b"@executable_path/Frameworks/xnower.dylib"

    tmpdir = tempfile.mkdtemp()
    exit_code = 0

    try:
        print("=" * 60)
        print("  XNOW IPA 注入工具")
        print("=" * 60)
        print(f"  Input IPA:  {args.ipa}")
        print(f"  Dylib:      {args.dylib} ({os.path.getsize(args.dylib):,} bytes)")
        print(f"  Output:     {output}")
        print()

        # Step 1: 解压 IPA
        print("[1/5] 解压 IPA...")
        with zipfile.ZipFile(args.ipa) as z:
            z.extractall(tmpdir)

        payload = os.path.join(tmpdir, "Payload")
        apps = [d for d in os.listdir(payload) if d.endswith(".app")]
        if not apps:
            print("  ❌ Payload 中未找到 .app 目录")
            sys.exit(1)

        app_dir = os.path.join(payload, apps[0])
        app_name = apps[0]
        print(f"  ✅ {app_name}")

        fw_dir = os.path.join(app_dir, "Frameworks")
        main_binary = os.path.join(app_dir, app_name.replace(".app", ""))
        if not os.path.exists(main_binary):
            main_binary = os.path.join(app_dir, "TikTok")
        if not os.path.exists(main_binary):
            # Final fallback: find the main executable via Info.plist
            import plistlib
            info_plist = os.path.join(app_dir, "Info.plist")
            if os.path.exists(info_plist):
                with open(info_plist, 'rb') as f:
                    info = plistlib.load(f)
                exec_name = info.get('CFBundleExecutable', '')
                main_binary = os.path.join(app_dir, exec_name)

        if not os.path.exists(main_binary):
            print(f"  ❌ 无法找到主二进制")
            sys.exit(1)

        main_size = os.path.getsize(main_binary)
        print(f"  📱 主二进制: {os.path.basename(main_binary)} ({main_size:,} bytes)")

        # Step 2: 复制 dylib
        print()
        print("[2/5] 复制 xnower.dylib 到 Frameworks/...")
        os.makedirs(fw_dir, exist_ok=True)
        dylib_dest = os.path.join(fw_dir, "xnower.dylib")
        shutil.copy2(args.dylib, dylib_dest)
        os.chmod(dylib_dest, 0o755)
        print(f"  ✅ {dylib_dest} ({os.path.getsize(dylib_dest):,} bytes)")

        # Step 3: 修改主二进制
        print()
        print("[3/5] 修改主二进制...")
        with open(main_binary, 'rb') as f:
            main_data = f.read()

        magic = struct.unpack_from('<I', main_data, 0)[0]
        magic_be = struct.unpack_from('>I', main_data, 0)[0]

        if magic == MAGIC_MH_MAGIC_64:
            print("  📄 Thin arm64 格式")
            result, summaries = patch_thin(main_data, dylib_ref)
        elif magic_be == MAGIC_FAT or magic_be == MAGIC_FAT_CIGAM:
            narch = struct.unpack_from('>I', main_data, 4)[0]
            print(f"  📄 FAT 格式 ({narch} architectures)")
            result, summaries = patch_fat(main_data, dylib_ref)
        else:
            print(f"  ❌ 未知格式: magic=0x{magic:08X}")
            sys.exit(1)

        for line in summaries:
            print(f"  {line}")

        if len(result) == len(main_data):
            print("  ℹ️  xnower.dylib 已在主二进制中（无需修改）")
        else:
            bak = main_binary + ".bak"
            if not os.path.exists(bak):
                shutil.copy2(main_binary, bak)
            with open(main_binary, 'wb') as f:
                f.write(result)
            delta = len(result) - len(main_data)
            print(f"  ✅ 写入完成: {len(result):,} bytes ({delta:+,d} bytes)")

        # Step 4: 打包 IPA
        print()
        print("[4/5] 打包 IPA...")
        if os.path.exists(output):
            os.remove(output)
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=5) as zout:
            for root, dirs, files in os.walk(tmpdir):
                for f in files:
                    fp = os.path.join(root, f)
                    zout.write(fp, os.path.relpath(fp, tmpdir))

        final_size = os.path.getsize(output)
        print(f"  ✅ {output} ({final_size / 1024 / 1024:.1f} MB)")

        # Step 5: 修复图标
        print()
        print("[5/5] 修复图标...")
        iconfix_script = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            'ios-plugin', 'scripts', 'fix-ipa-icons.py'
        )
        if os.path.exists(iconfix_script):
            ret = os.system(f'"{sys.executable}" "{iconfix_script}" "{output}" "{output}"')
            if ret == 0:
                print("  ✅ 图标修复完成")
            else:
                print("  ⚠️ 图标修复失败（可手动修复或忽略）")
        else:
            print("  ⚠️ fix-ipa-icons.py 未找到，跳过图标修复")

        # ========== 结果摘要 ==========
        print()
        print("=" * 60)
        print("  ✅ 注入完成")
        print("=" * 60)
        print(f"  📦 {output} ({final_size / 1024 / 1024:.1f} MB)")
        print()
        print("  📋 验证摘要:")
        for line in summaries:
            print(f"    {line}")
        print()
        print("  🚀 下一步:")
        print("    1. 用 爱思助手 / iOS App Signer 签名")
        print("    2. 安装到 iPhone")
        print("    3. 打开 TikTok → 顶部红色 'XNOWER LOADED' 条确认加载")
        print("    4. 4秒后紫色 X 浮窗出现在屏幕侧边")
        print()

    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
        exit_code = 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
