#!/usr/bin/env python3
"""Build minimal test dylib on VPS"""
import paramiko, os

HOST = '192.129.210.52'
USER = 'root'
PASSWORD = '0ISvaWdV88lLq871Re'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
PROJECT = r'F:\summer\vs-code\XNOW-Flow'

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)

def run(cmd, timeout=120):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    ec = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        for line in out.strip().split('\n')[-10:]: print(f"  {line}")
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-5:]: print(f"  ERR: {line}")

print("[1] Writing minimal dylib source...")
run(f"""
cat > {REMOTE}/minimal.c << 'EOF'
#include <stdio.h>
__attribute__((constructor)) static void init() {{
    // Just a simple function that compiles without frameworks
}}
int test_function() {{ return 42; }}
EOF
""", 30)

print("[2] Compiling minimal dylib (no frameworks)...")
run(f"""
cd {REMOTE}
clang-16 -target arm64-apple-ios16.5 -isysroot {SDK} -c minimal.c -o minimal.o
{LD} -arch arm64 -dylib -platform_version ios 16.5 16.5 -o minimal.dylib minimal.o -lSystem -syslibroot {SDK} -install_name @executable_path/Frameworks/minimal.dylib 2>&1
file minimal.dylib
""", 60)

print("[3] Check format...")
run(f"""
cd {REMOTE}
python3 -c "
import struct
with open('minimal.dylib', 'rb') as f:
    data = f.read()
ncmds = struct.unpack_from('<I', data, 16)[0]
print(f'ncmds={ncmds}')
off = 32
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    if c == 0x80000022:
        print(f'  [{i}] PRIV_DYLD_INFO (will convert)')
    elif c == 0x22:
        vals = struct.unpack_from('<IIIIIIII', data, off+8)
        nz = [(k,v) for k,v in zip(['R','B','L','E'],[vals[0],vals[2],vals[4],vals[6]]) if v!=0]
        print(f'  [{i}] LC_DYLD_INFO_ONLY: {nz}')
    elif c in [0x36, 0x35]:
        print(f'  [{i}] CHAINED FIXUPS! BAD!')
    off += cs
"
""", 30)

print("[4] Converting private cmd...")
run(f"""
cd {REMOTE}
python3 -c "
import struct
with open('minimal.dylib', 'rb') as f:
    data = bytearray(f.read())
ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    if c == 0x80000022:
        struct.pack_into('<I', data, off, 0x22)
        print(f'Converted [{i}]')
    off += cs
with open('minimal-converted.dylib', 'wb') as f:
    f.write(data)
print('Done')
"
ls -la minimal-converted.dylib
""", 30)

print("[5] Downloading...")
sftp = ssh.open_sftp()
sftp.get(f"{REMOTE}/minimal-converted.dylib", os.path.join(PROJECT, 'build-artifacts-ci', 'minimal.dylib'))
sftp.close()
print("  Downloaded!")

ssh.close()
print("\n=== Done ===")
