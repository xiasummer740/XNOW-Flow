#!/usr/bin/env python3
"""Build xnower.dylib on VPS with iOS 11.4 SDK (older format = iOS 16 compatible)"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
PASSWORD = 'XNW_VPS_PASSWORD_FROM_ENV'
REMOTE = '/root/xnow-build'
SDK_OLD = '/opt/theos/sdks/iPhoneOS11.4.sdk'
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)

def run(cmd, timeout=120):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    ec = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        for line in out.strip().split('\n')[-20:]: print(f'  {line}')
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-10:]: print(f'  ERR: {line}')
    return out

# Upload sources
print("[Upload] Sources...")
sftp = ssh.open_sftp()
src_dir = os.path.join(PROJECT, 'ios-plugin', 'xnow-dylib')
run(f"mkdir -p {REMOTE}/ios11", 30)
for f in os.listdir(src_dir):
    if f.endswith(('.m', '.h', '.plist')):
        sftp.put(os.path.join(src_dir, f), f"{REMOTE}/{f}")
sftp.close()

# Compile
print("[1] Compiling with iOS 11.4 SDK...")
CFLAGS = f"-target arm64-apple-ios11.4 -isysroot {SDK_OLD} -fobjc-arc -O2 -Wno-everything -DNDEBUG -c"
SRCS = ['XNOWER.m', 'XNStartup.m', 'WsClient.m', 'CommandEngine.m', 'DeviceStatus.m',
        'TikTokHooks.m', 'XNFloatingPanel.m', 'AccountManager.m', 'AccountPool.m', 'AccountSwitcher.m', 'AccountSnapshotter.m']

for src in SRCS:
    obj = f"ios11/{src.replace('.m', '.o')}"
    out = run(f"cd {REMOTE} && clang-16 {CFLAGS} {src} -o {obj} 2>&1", 60)
    has_err = 'error:' in out.lower() or 'Error:' in out
    print(f"  {'FAIL' if has_err else 'OK'}: {src}")

# Link
print("[2] Linking with ld64.lld (iOS 11.4 target)...")
OBJS = ' '.join([f"ios11/{s.replace('.m', '.o')}" for s in SRCS])
LINK_CMD = f"cd {REMOTE} && ld64.lld -arch arm64 -dylib -platform_version ios 11.4 11.4 -o ios11/xnower.dylib {OBJS} -lSystem -lobjc -framework Foundation -framework UIKit -framework CoreGraphics -framework CFNetwork -framework WebKit -syslibroot {SDK_OLD} -install_name @executable_path/Frameworks/xnower.dylib"
run(LINK_CMD, 120)

# Check and convert
print("[3] Check format + convert if needed...")
check_cmd = '''cd /root/xnow-build/ios11 && python3 -c "
import struct
with open('xnower.dylib', 'rb') as f:
    data = bytearray(f.read())
ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
has_dyld = has_priv = has_chain = False
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    if c == 0x22: has_dyld = True
    if c == 0x80000022: has_priv = True
    if c == 0x36: has_chain = True
    if c == 0x80000022:
        struct.pack_into('<I', data, off, 0x22)
        print(f'  CONVERTED PRIV_DYLD_INFO -> LC_DYLD_INFO_ONLY [{i}]')
    off += cs
print(f'Has DYLD_INFO: {has_dyld}, Has PRIV: {has_priv}, Has CHAINED: {has_chain}')
with open('xnower.dylib', 'wb') as f:
    f.write(data)
"
'''
run(check_cmd)

# Verify
print("[4] Verify...")
verify_cmd = '''cd /root/xnow-build/ios11 && python3 -c "
import struct
with open('xnower.dylib', 'rb') as f:
    data = f.read()
ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    if c in [0x22, 0x36, 0x35, 0x80000022, 0x80000033, 0x80000034, 0x0d, 0x32]:
        name = {0x22:'DYLD_INFO',0x36:'CHAINED',0x35:'EXPORTS',0x80000022:'PRIV_DYLD',0x80000033:'PRIV_EXP',0x80000034:'PRIV_CHAIN'}.get(c,'')
        if c in [0x22, 0x80000022]:
            vals = struct.unpack_from('<IIIIIIIIII', data, off+8)
            print(f'  [{i:2d}] 0x{c:08x} {name} r={vals[0]}:{vals[1]} b={vals[2]}:{vals[3]} e={vals[8]}:{vals[9]}')
        else:
            print(f'  [{i:2d}] 0x{c:08x} {name}')
    off += cs
print(f'Size: {len(data)} bytes')
"
'''
print(run(verify_cmd))

# Download
if os.path.exists('build-artifacts-ci/ios11-xnower.dylib'):
    os.remove('build-artifacts-ci/ios11-xnower.dylib')
print("[5] Downloading...")
sftp = ssh.open_sftp()
sftp.get(f"{REMOTE}/ios11/xnower.dylib", os.path.join(PROJECT, 'build-artifacts-ci', 'ios11-xnower.dylib'))
sftp.close()
ssh.close()
print("=== Done ===")
