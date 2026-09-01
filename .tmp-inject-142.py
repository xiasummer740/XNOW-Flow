#!/usr/bin/env python3
"""一次性：把 v1.4.142 dylib 上传 VPS → vps-inject 注入 → 生成 TikTok_XNOW_v1.4.142_BH.ipa → 下载本地
142 = 141 闪退修复版（XOR 混淆 TikTok 私有类名 + XNRequestHooks 改名）"""
import paramiko, os, sys

PROJECT = os.path.dirname(os.path.abspath(__file__))
env = {}
for line in open(os.path.join(PROJECT, '.env.local'), encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, _, v = line.partition('='); env[k.strip()] = v.strip()
PWD = env.get('XNW_VPS_PASSWORD', '')

LOCAL_DYLIB = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-142', 'xnower.dylib')
OUT = 'TikTok_XNOW_v1.4.142_BH.ipa'

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

# 1. 上传 dylib
print("[1] 上传 xnower.dylib → /root/xnow-build/xnower-142.dylib ...")
sftp = ssh.open_sftp()
sftp.put(LOCAL_DYLIB, '/root/xnow-build/xnower-142.dylib')
sftp.close()
print("  uploaded")

# 2. 找基础 IPA：无 43.7.0 原始包，用 static 里最新的已注入版本作为 base 连续注入
print("[2] 定位基础 IPA ...")
out, _ = run("ls -t /opt/xnow-flow/static/TikTok_XNOW_v1.4.1[0-9][0-9]_BH.ipa 2>/dev/null | head -1")
base_ipa = out.strip().split('\n')[0].strip() if out.strip() else None
if not base_ipa:
    print("❌ 未找到可用的 base IPA"); ssh.close(); sys.exit(1)
print(f"  基础 IPA: {base_ipa}")

# 3. 注入
print(f"[3] vps-inject: {base_ipa} + xnower-142.dylib → {OUT} ...")
run(f"cd /opt/xnow-flow && python3 vps-inject.py {base_ipa} /root/xnow-build/xnower-142.dylib /opt/xnow-flow/static/{OUT} 2>&1", 300)

# 4. 验证产物
print("[4] 验证 ...")
out, _ = run(f"ls -l /opt/xnow-flow/static/{OUT} && python3 -c \"import zipfile;z=zipfile.ZipFile('/opt/xnow-flow/static/{OUT}');print('  zip OK,',len(z.namelist()),'entries')\"")
ok = OUT in out or 'zip OK' in out

# 5. 下载本地
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
