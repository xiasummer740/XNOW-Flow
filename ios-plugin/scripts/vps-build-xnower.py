#!/usr/bin/env python3
"""
vps-build-xnower.py — Build xnower.dylib on VPS
"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
PASSWORD = '0ISvaWdV88lLq871Re'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
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
        for line in out.strip().split('\n')[-10:]:
            print(f"  {line}")
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-5:]:
            print(f"  ERR: {line}")
    return out

# Upload sources
print("[Upload] Sources...")
sftp = ssh.open_sftp()
src_dir = os.path.join(PROJECT, 'ios-plugin', 'xnow-dylib')
run(f"mkdir -p {REMOTE}", 30)
for f in os.listdir(src_dir):
    if f.endswith(('.m', '.h', '.plist')):
        sftp.put(os.path.join(src_dir, f), f"{REMOTE}/{f}")

# Upload fix script
fix_script = os.path.join(PROJECT, 'ios-plugin', 'scripts', '_fix_xnwindow.py')
with open(fix_script, 'w') as f:
    f.write("""import re
with open('/root/xnow-build/XNWindowHelper.h', 'r') as fh:
    c = fh.read()
new_fn = '''static inline UIWindow *XN_ActiveWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                if ([scene isKindOfClass:UIWindowScene.class]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) return w;
                    }
                }
            }
        }
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) return w;
    }
    return UIApplication.sharedApplication.keyWindow;
}'''
c = re.sub(r'static inline UIWindow \\*XN_ActiveWindow\\(void\\) \\{.*?^\\}', new_fn, c, count=1, flags=re.DOTALL|re.MULTILINE)
with open('/root/xnow-build/XNWindowHelper.h', 'w') as fh:
    fh.write(c)
print('Fixed XNWindowHelper.h')
""")
sftp.put(fix_script, f"{REMOTE}/fix_xn.py")
os.remove(fix_script)

# Upload check script
check_script = os.path.join(PROJECT, 'ios-plugin', 'scripts', '_check_format.py')
with open(check_script, 'w') as f:
    f.write("""import struct
with open('/root/xnow-build/xnower.dylib', 'rb') as fh:
    data = fh.read()
ncmds = struct.unpack_from('<I', data, 16)[0]
print(f'ncmds={ncmds}')
off = 32
has_priv = has_chain = has_info = False
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    names = {0x22:'DYLD_INFO_ONLY', 0x36:'CHAINED_FIXUPS', 0x35:'EXPORTS_TRIE',
             0x80000022:'PRIV_DYLD_INFO', 0x80000033:'PRIV_EXPORTS', 0x80000034:'PRIV_CHAINED'}
    name = names.get(c, '')
    if name:
        print(f'  [{i}] {name}')
    if c in [0x80000022, 0x80000033, 0x80000034]:
        has_priv = True
    if c == 0x36:
        has_chain = True
    if c == 0x22:
        has_info = True
        vals = struct.unpack_from('<IIIIIIII', data, off+8)
        nz = [(k,v) for k,v in zip(['R','B','L','E'],[vals[0],vals[2],vals[4],vals[6]]) if v!=0]
        if nz: print(f'    data: {nz}')
    off += cs
if not has_chain and not has_priv:
    print('NO CHAINED/PRIVATE FIXUPS!')
    if has_info:
        print('Has LC_DYLD_INFO_ONLY - iOS 16 compatible!')
else:
    print('WARNING: Has fixup commands')
""")
sftp.put(check_script, f"{REMOTE}/check_format.py")
os.remove(check_script)
sftp.close()

# Step 1: Fix XNWindowHelper.h
print("\n[1] Fixing XNWindowHelper.h...")
run(f"cd {REMOTE} && python3 fix_xn.py", 30)

# Step 2: Compile
print("[2] Compiling...")
CFLAGS = f"-target arm64-apple-ios16.5 -isysroot {SDK} -fobjc-arc -O2 -Wno-everything -DNDEBUG -c"
SRCS = ['XNOWER.m', 'WsClient.m', 'CommandEngine.m', 'DeviceStatus.m',
        'TikTokHooks.m', 'XNFloatingPanel.m', 'AccountManager.m']

for src in SRCS:
    obj = src.replace('.m', '.o')
    out = run(f"cd {REMOTE} && clang-16 {CFLAGS} {src} -o {obj} 2>&1", 60)
    has_err = 'error:' in out.lower() or 'Error:' in out
    print(f"  {'FAIL' if has_err else 'OK'}: {src}")

# Step 3: Link
print("[3] Linking...")
OBJS = ' '.join([s.replace('.m', '.o') for s in SRCS])
LINK_CMD = f"cd {REMOTE} && {LD} -arch arm64 -dylib -platform_version ios 16.5 16.5 -o xnower.dylib {OBJS} -lSystem -lobjc -framework Foundation -framework UIKit -framework CoreGraphics -framework CFNetwork -framework WebKit -syslibroot {SDK} -install_name @executable_path/Frameworks/xnower.dylib"
out = run(LINK_CMD, 120)

# Step 4: Check format
print("[4] Checking format...")
run(f"cd {REMOTE} && python3 check_format.py", 30)

# Step 5: Download
print("[5] Downloading...")
sftp = ssh.open_sftp()
local_dylib = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-lld.dylib')
try:
    sftp.get(f"{REMOTE}/xnower.dylib", local_dylib)
    size = os.path.getsize(local_dylib)
    print(f"  Downloaded: {local_dylib} ({size} bytes)")
except:
    print("  Download failed - check if build succeeded")
sftp.close()

ssh.close()
print("\n=== Done ===")
