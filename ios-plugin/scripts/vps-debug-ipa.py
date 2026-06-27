#!/usr/bin/env python3
"""
vps-debug-ipa.py — 在 VPS 上检查 IPA 注入后的二进制完整性
用法: python vps-debug-ipa.py (自动上传并检查)
"""

import paramiko, os, sys, json, tempfile

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOCAL_IPA = os.path.join(PROJECT_DIR, "TikTok_XNOW_v2.ipa")

REMOTE_DIR = "/root/xnow-debug"
REMOTE_IPA = f"{REMOTE_DIR}/TikTok_XNOW_v2.ipa"


def run_ssh(ssh, cmd, timeout=30):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    exit_code = stdout.channel.recv_exit_status()
    return stdout.read().decode(), stderr.read().decode(), exit_code


def main():
    print("=" * 60)
    print("  IPA 二进制完整性检查")
    print("=" * 60)

    if not os.path.exists(LOCAL_IPA):
        print(f"[ERR] 未找到: {LOCAL_IPA}")
        sys.exit(1)

    print(f"\n[1/4] 连接 VPS ...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)
    print("  [OK] 连接成功")

    ssh.exec_command(f"mkdir -p {REMOTE_DIR}")

    print(f"\n[2/4] 上传 IPA 到 VPS ...")
    sftp = ssh.open_sftp()
    sftp.put(LOCAL_IPA, REMOTE_IPA)
    sftp.close()
    print("  [OK] 上传完成")

    print(f"\n[3/4] 在 VPS 上检查二进制 ...")

    # Install Python3 and pyelftools-equivalent (for Mach-O parsing)
    # Actually, let's just use basic python with struct
    check_script = """
import struct, zipfile, tempfile, os, shutil

ipa_path = "/root/xnow-debug/TikTok_XNOW_v2.ipa"
tmpdir = tempfile.mkdtemp()

try:
    # Extract IPA
    with zipfile.ZipFile(ipa_path) as z:
        z.extractall(tmpdir)

    payload = os.path.join(tmpdir, "Payload")
    for item in os.listdir(payload):
        if item.endswith(".app"):
            app_dir = os.path.join(payload, item)
            binary_name = item[:-4]
            binary_path = os.path.join(app_dir, binary_name)
            dylib_path = os.path.join(app_dir, "Frameworks", "xnower.dylib")

            print(f"\\nApp: {item}")
            print(f"Binary: {binary_name}")

            # Check dylib exists
            if os.path.exists(dylib_path):
                dylib_size = os.path.getsize(dylib_path)
                print(f"[OK] xnower.dylib found: {dylib_size} bytes")
            else:
                print(f"[ERR] xnower.dylib NOT FOUND!")

            # Check dylib is in the main binary
            with open(binary_path, "rb") as f:
                data = f.read()

            if b"xnower.dylib" in data:
                print(f"[OK] xnower.dylib LC_LOAD_DYLIB found in binary")
                # Find the exact location
                idx = data.find(b"xnower.dylib")
                print(f"     Found at file offset: 0x{idx:x}")
            else:
                print(f"[ERR] xnower.dylib NOT in binary load commands!")

            # Parse Mach-O header to verify
            magic = struct.unpack_from("<I", data, 0)[0]
            MH_MAGIC_64 = 0xFEEDFACF
            FAT_MAGIC = 0xBEBAFECA

            if magic == MH_MAGIC_64:
                ncmds = struct.unpack_from("<I", data, 16)[0]
                sizeofcmds = struct.unpack_from("<I", data, 20)[0]
                cputype = struct.unpack_from("<I", data, 4)[0]
                filetype = struct.unpack_from("<I", data, 12)[0]

                expected_arm64 = 0x0100000c  # CPU_TYPE_ARM64

                print(f"\\nMach-O Header:")
                print(f"  Magic: 0x{magic:08x} {'(MH_MAGIC_64)' if magic == MH_MAGIC_64 else '(UNKNOWN)'}")
                print(f"  CPUType: 0x{cputype:08x} {'(ARM64)' if cputype == 0x0100000c else '(UNKNOWN)'}")
                print(f"  FileType: 0x{filetype:04x}")
                print(f"  ncmds: {ncmds}")
                print(f"  sizeofcmds: {sizeofcmds}")

                # List all load commands
                cmd_offset = 32
                print(f"\\nLoad Commands:")
                for i in range(min(ncmds, 30)):  # Show first 30
                    if cmd_offset + 8 > len(data):
                        break
                    cmd, cmdsize = struct.unpack_from("<II", data, cmd_offset)

                    cmd_names = {
                        0x01: "LC_SEGMENT_32", 0x02: "LC_SYMTAB", 0x03: "LC_SYMSEG",
                        0x05: "LC_DYSYMTAB", 0x0B: "LC_LOAD_DYLIB", 0x0C: "LC_ID_DYLIB",
                        0x0D: "LC_LOAD_DYLINKER", 0x0E: "LC_DYLD_INFO", 0x0F: "LC_DYLD_INFO_ONLY",
                        0x19: "LC_UUID", 0x1B: "LC_VERSION_MIN_IPHONEOS",
                        0x1D: "LC_SOURCE_VERSION", 0x1E: "LC_MAIN", 0x1F: "LC_LOAD_WEAK_DYLIB",
                        0x20: "LC_CODE_SIGNATURE", 0x21: "LC_SEGMENT_SPLIT_INFO",
                        0x22: "LC_REEXPORT_DYLIB", 0x24: "LC_ENCRYPTION_INFO",
                        0x25: "LC_DYLD_INFO", 0x26: "LC_DYLD_INFO_ONLY",
                        0x8000001D: "LC_LOAD_DYLIB (ordered)",
                        0x80000022: "LC_LAZY_LOAD_DYLIB",
                        0x19: "LC_UUID",
                        0x8000001C: "LC_LOAD_WEAK_DYLIB",
                        0x2E: "LC_SEGMENT_64 (__LINKEDIT)",
                    }

                    cmd_name = cmd_names.get(cmd, f"UNKNOWN(0x{cmd:08x})")

                    # For LC_LOAD_DYLIB, show the dylib name
                    detail = ""
                    if cmd in (0x0B, 0x8000001D, 0x80000022, 0x8000001C, 0x0C):
                        if cmd_offset + 24 < len(data):
                            name_off = cmd_offset + 24
                            end = data.find(b'\\x00', name_off, cmd_offset + cmdsize)
                            if end > name_off:
                                detail = data[name_off:end].decode('utf-8', errors='replace')

                    print(f"  [{i}] {cmd_name} (size={cmdsize}) {detail}")
                    cmd_offset += cmdsize

                    if cmd == 0x2E:  # __LINKEDIT found
                        # Read segment info
                        segname = data[cmd_offset+8:cmd_offset+24].split(b'\\x00')[0].decode('ascii', errors='replace')
                        fileoff = struct.unpack_from("<Q", data, cmd_offset + 32)[0]
                        filesize = struct.unpack_from("<Q", data, cmd_offset + 40)[0]
                        print(f"       segname: {segname}")
                        print(f"       fileoff: 0x{fileoff:x}")
                        print(f"       filesize: 0x{filesize:x}")
                        print(f"       Expected fileoff: 0x{(cmd_offset + cmdsize + 16384) & ~16383:x} (after alignment)")

                # Count LC_LOAD_DYLIB commands
                ldl_count = 0
                ldl_xnow = 0
                cmd_offset = 32
                for i in range(ncmds):
                    if cmd_offset + 8 > len(data):
                        break
                    cmd, cmdsize = struct.unpack_from("<II", data, cmd_offset)
                    if cmd in (0x0B, 0x8000001D, 0x80000022):
                        ldl_count += 1
                        name_off = cmd_offset + 24
                        end = data.find(b'\\x00', name_off, cmd_offset + cmdsize)
                        if end > name_off:
                            name = data[name_off:end]
                            if b'xnower' in name:
                                ldl_xnow += 1
                    cmd_offset += cmdsize

                print(f"\\n  Total LC_LOAD_DYLIB: {ldl_count}")
                print(f"  xnower.dylib entries: {ldl_xnow}")

            elif magic == FAT_MAGIC:
                narch = struct.unpack_from("<I", data, 4)[0]
                print(f"FAT binary with {narch} architectures")
                print("  Need to check arm64 slice specifically")
            else:
                print(f"Unknown magic: 0x{magic:08x}")

            # Check dylib header
            print(f"\\n--- Dylib Check ---")
            if os.path.exists(dylib_path):
                with open(dylib_path, "rb") as f:
                    d = f.read()
                d_magic = struct.unpack_from("<I", d, 0)[0]
                if d_magic == 0xFEEDFACF:
                    d_ncmds = struct.unpack_from("<I", d, 16)[0]
                    d_cputype = struct.unpack_from("<I", d, 4)[0]
                    print(f"  Magic: 0x{d_magic:08x} (MH_MAGIC_64)")
                    print(f"  CPUType: 0x{d_cputype:08x}")
                    print(f"  ncmds: {d_ncmds}")
                    ... OK
                else:
                    print(f"  [ERR] Invalid magic: 0x{d_magic:08x}")
    else:
        print(f"[ERR] No .app found in Payload!")

finally:
    shutil.rmtree(tmpdir, ignore_errors=True)
"""

    # Write debug script to VPS and run
    ssh.exec_command(f"cat > {REMOTE_DIR}/check.py << 'PYEOF'\n{check_script}\nPYEOF")
    out, err, code = run_ssh(ssh, f"python3 {REMOTE_DIR}/check.py", timeout=60)

    print(out)
    if err.strip():
        print(f"STDERR: {err.strip()[:500]}")

    print(f"\n[4/4] 清理 ...")
    ssh.exec_command(f"rm -rf {REMOTE_DIR}")
    ssh.close()
    print("  done")


if __name__ == "__main__":
    main()
