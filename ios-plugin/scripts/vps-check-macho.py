#!/usr/bin/env python3
"""XNOW IPA 诊断脚本 — 在 VPS 上检查注入后的二进制"""

import struct, zipfile, tempfile, os, sys, shutil


def check_ipa(ipa_path):
    tmpdir = tempfile.mkdtemp()
    try:
        print(f"\n[1] 解压 IPA ...")
        with zipfile.ZipFile(ipa_path) as z:
            z.extractall(tmpdir)

        payload = os.path.join(tmpdir, "Payload")
        for item in os.listdir(payload):
            if not item.endswith(".app"):
                continue
            app_dir = os.path.join(payload, item)
            binary_name = item[:-4]
            binary_path = os.path.join(app_dir, binary_name)
            dylib_path = os.path.join(app_dir, "Frameworks", "xnower.dylib")

            print(f"\nApp: {item}")
            print(f"Binary: {binary_name}")

            # --- Dylib existence ---
            if os.path.exists(dylib_path):
                dylib_size = os.path.getsize(dylib_path)
                print(f"[OK] xnower.dylib: {dylib_size} bytes")
            else:
                print(f"[ERR] xnower.dylib NOT FOUND in Frameworks/")

            # --- Read main binary ---
            with open(binary_path, "rb") as f:
                data = f.read()

            # Check LC_LOAD_DYLIB
            if b"xnower.dylib" in data:
                idx = data.find(b"xnower.dylib")
                print(f"[OK] xnower.dylib LC_LOAD_DYLIB at offset 0x{idx:x}")
            else:
                print(f"[ERR] xnower.dylib NOT in load commands!")

            # --- Parse Mach-O header ---
            magic = struct.unpack_from("<I", data, 0)[0]
            MH_MAGIC_64 = 0xFEEDFACF
            FAT_MAGIC = 0xBEBAFECA
            FAT_MAGIC_BE = 0xCAFEBABE

            if magic == MH_MAGIC_64:
                _check_single_arch(data, binary_name)
            elif magic in (FAT_MAGIC, FAT_MAGIC_BE):
                _check_fat(data, binary_name)
            else:
                print(f"[ERR] Unknown magic: 0x{magic:08x}")

            # --- Check dylib header ---
            if os.path.exists(dylib_path):
                print(f"\n--- Dylib ---")
                with open(dylib_path, "rb") as f:
                    d = f.read()
                d_magic = struct.unpack_from("<I", d, 0)[0]
                if d_magic == 0xFEEDFACF:
                    d_ncmds = struct.unpack_from("<I", d, 16)[0]
                    d_cputype = struct.unpack_from("<I", d, 4)[0]
                    print(f"  Magic: MH_MAGIC_64")
                    print(f"  CPUType: ARM64" if d_cputype == 0x0100000c else f"  CPUType: 0x{d_cputype:x}")
                    print(f"  ncmds: {d_ncmds}")
                    print(f"  [OK] Valid Mach-O")
                else:
                    print(f"  [ERR] Invalid magic: 0x{d_magic:08x}")
        return True
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _check_single_arch(data, name):
    ncmds = struct.unpack_from("<I", data, 16)[0]
    sizeofcmds = struct.unpack_from("<I", data, 20)[0]
    cputype = struct.unpack_from("<I", data, 4)[0]
    flags = struct.unpack_from("<I", data, 24)[0]

    print(f"\n  Mach-O Header:")
    print(f"    Magic: MH_MAGIC_64")
    print(f"    CPU: {'arm64' if cputype == 0x0100000c else f'0x{cputype:x}'}")
    print(f"    ncmds: {ncmds}")
    print(f"    sizeofcmds: {sizeofcmds} (0x{sizeofcmds:x})")

    # List all load commands
    cmd_offset = 32
    dylib_count = 0
    xnower_count = 0
    linkedit_found = False

    for i in range(ncmds):
        if cmd_offset + 8 > len(data):
            print(f"    [ERR] Truncated at cmd {i}")
            break

        cmd, cmdsize = struct.unpack_from("<II", data, cmd_offset)
        if cmd_offset + cmdsize > len(data):
            print(f"    [ERR] Command {i} overflows file (size={cmdsize})")
            break

        cmd_names = {
            0x01: "LC_SEGMENT_32", 0x02: "LC_SYMTAB", 0x19: "LC_UUID",
            0x0B: "LC_LOAD_DYLIB", 0x0C: "LC_ID_DYLIB",
            0x0D: "LC_LOAD_DYLINKER", 0x0F: "LC_DYLD_INFO_ONLY",
            0x1B: "LC_VERSION_MIN_IPHONEOS", 0x1D: "LC_SOURCE_VERSION",
            0x1E: "LC_MAIN", 0x1F: "LC_LOAD_WEAK_DYLIB",
            0x20: "LC_CODE_SIGNATURE", 0x21: "LC_SEGMENT_SPLIT_INFO",
            0x22: "LC_REEXPORT_DYLIB", 0x24: "LC_ENCRYPTION_INFO",
            0x2E: "LC_SEGMENT_64 (__LINKEDIT)",
            0x8000001D: "LC_LOAD_DYLIB (ordered)",
            0x80000022: "LC_LAZY_LOAD_DYLIB",
        }

        cname = cmd_names.get(cmd, f"0x{cmd:08x}")

        # For dylib load commands, show name
        detail = ""
        cmd_type_for_name = (0x0B, 0x0C, 0x1F, 0x22, 0x8000001D, 0x80000022)
        if cmd in cmd_type_for_name and cmd_offset + 24 < len(data):
            ne = data.find(b'\x00', cmd_offset + 24, cmd_offset + cmdsize)
            if ne > cmd_offset + 24:
                dname = data[cmd_offset+24:ne].decode('utf-8', errors='replace')
                detail = f" -> {dname}"
                if b'xnower' in data[cmd_offset+24:ne]:
                    xnower_count += 1
                dylib_count += 1

        # Check __LINKEDIT alignment
        if cmd == 0x2E:  # LC_SEGMENT_64
            linkedit_found = True
            segname = data[cmd_offset+8:cmd_offset+24].split(b'\x00')[0].decode('ascii', errors='replace')
            fileoff = struct.unpack_from("<Q", data, cmd_offset + 32)[0]
            filesize = struct.unpack_from("<Q", data, cmd_offset + 40)[0]
            print(f"    [{i}] LC_SEGMENT_64: {segname} fileoff=0x{fileoff:x} filesize=0x{filesize:x}")
            print(f"         Expected fileoff after load cmds: 0x{(32 + sizeofcmds + 16383) & ~16383:x}")
        elif cmd == 0x20:  # LC_CODE_SIGNATURE
            sig_off = struct.unpack_from("<I", data, cmd_offset + 8)[0]
            sig_size = struct.unpack_from("<I", data, cmd_offset + 12)[0]
            print(f"    [{i}] LC_CODE_SIGNATURE: offset=0x{sig_off:x} size=0x{sig_size:x}")
        else:
            print(f"    [{i}] {cname} (size={cmdsize}){detail}")

        cmd_offset += cmdsize

    if not linkedit_found:
        print(f"    [WARN] __LINKEDIT not found in load commands!")

    print(f"\n  Summary:")
    print(f"    Total LC_LOAD_DYLIB: {dylib_count}")
    print(f"    xnower.dylib refs: {xnower_count}")
    if xnower_count > 0:
        print(f"    [OK] xnower.dylib properly injected")
    else:
        print(f"    [ERR] xnower.dylib injection FAILED!")


def _check_fat(data, name):
    narch = struct.unpack_from("<I", data, 4)[0]
    print(f"\n  FAT binary with {narch} archs")
    for i in range(narch):
        off = 8 + i * 20
        cpu_type = struct.unpack_from("<I", data, off)[0]
        cpu_sub = struct.unpack_from("<I", data, off + 4)[0]
        slice_off = struct.unpack_from("<I", data, off + 8)[0]
        slice_size = struct.unpack_from("<I", data, off + 12)[0]
        arch_name = "arm64" if cpu_type == 0x0100000c else f"0x{cpu_type:x}"
        print(f"    [{i}] CPU={arch_name} offset=0x{slice_off:x} size=0x{slice_size:x}")
        if cpu_type == 0x0100000c:
            slice_data = data[slice_off:slice_off+slice_size]
            _check_single_arch(slice_data, f"{name}[arm64]")


if __name__ == "__main__":
    ipa = sys.argv[1] if len(sys.argv) > 1 else "/root/xnow-debug/TikTok_XNOW_v2.ipa"
    if not os.path.exists(ipa):
        print(f"[ERR] IPA not found: {ipa}")
        sys.exit(1)
    check_ipa(ipa)
