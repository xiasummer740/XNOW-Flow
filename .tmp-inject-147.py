#!/usr/bin/env python3
"""一次性：147（follow 手势 _sendActionWithGestureRecognizer 修复）打包 TikTok_XNOW_v1.4.147_BH.ipa"""
import paramiko, os, sys

PROJECT = os.path.dirname(os.path.abspath(__file__))
env = {}
for line in open(os.path.join(PROJECT, '.env.local'), encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, _, v = line.partition('='); env[k.strip()] = v.strip()
PWD = env.get('XNW_VPS_PASSWORD', '')

LOCAL_DYLIB = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-147', 'xnower.dylib')
OUT = 'TikTok_XNOW_v1.4.147_BH.ipa'

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', PWD, timeout=15)

def run(cmd, timeout=180):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    ec = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    tail = '\n'.join(out.strip().split('\n')[-12:])
    if tail.strip():
        print(f"  {tail}")
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-6:]:
            print(f"  ERR: {line}")
    return out, ec

print("[1] 上传 xnower.dylib → /root/xnow-build/xnower-147.dylib ...")
sftp = ssh.open_sftp()
sftp.put(LOCAL_DYLIB, '/root/xnow-build/xnower-147.dylib')
sftp.close()
print("  uploaded")

print("[2] 定位基础 IPA ...")
out, _ = run("ls -t /opt/xnow-flow/static/TikTok_XNOW_v1.4.14[0-9]_BH.ipa 2>/dev/null | head -1")
base_ipa = out.strip().split('\n')[0].strip() if out.strip() else None
if not base_ipa:
    print("❌ 未找到 base IPA"); ssh.close(); sys.exit(1)
print(f"  基础 IPA: {base_ipa}")

print(f"[3] vps-inject: → {OUT} ...")
run(f"cd /opt/xnow-flow && python3 vps-inject.py {base_ipa} /root/xnow-build/xnower-147.dylib /opt/xnow-flow/static/{OUT} 2>&1", 300)

print("[4] 验证 ...")
out, _ = run(f"ls -l /opt/xnow-flow/static/{OUT} && python3 -c \"import zipfile;z=zipfile.ZipFile('/opt/xnow-flow/static/{OUT}');print('  zip OK,',len(z.namelist()),'entries')\"")
ok = OUT in out or 'zip OK' in out

if ok:
    print("[5] 下载本地 ...")
    sftp = ssh.open_sftp()
    sftp.get(f'/opt/xnow-flow/static/{OUT}', os.path.join(PROJECT, OUT))
    sftp.close()
    sz = os.path.getsize(os.path.join(PROJECT, OUT))
    print(f"  ✅ {OUT} ({sz/1024/1024:.1f} MB)")
else:
    print("❌ 注入失败，未下载")
ssh.close()
print("=== Done ===")
