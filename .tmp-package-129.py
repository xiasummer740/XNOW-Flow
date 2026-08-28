#!/usr/bin/env python3
"""打包 TikTok_XNOW_v1.4.129_BH.ipa + 上传 VPS static"""
import subprocess, os, sys, paramiko

PROJECT = os.path.dirname(os.path.abspath(__file__))
DYLIB = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-129', 'xnower.dylib')
VERSION = '1.4.129'
OUT = f'TikTok_XNOW_v{VERSION}_BH.ipa'

# 1. 打包
print(f"[1] 打包 {OUT}...")
r = subprocess.run([sys.executable, 'build-bh-ipa.py', DYLIB, VERSION],
                   cwd=PROJECT, capture_output=True, text=True, timeout=600)
print(r.stdout[-2500:])
if r.returncode != 0:
    print("❌ 打包失败"); sys.exit(1)

# 2. 上传
print(f"\n[2] 上传 {OUT} → /opt/xnow-flow/static/...")
env = {}
with open(os.path.join(PROJECT, '.env.local'), encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, _, v = line.partition('='); env[k.strip()] = v.strip()
ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', env.get('XNW_VPS_PASSWORD', ''), timeout=15)
sftp = ssh.open_sftp()
local = os.path.join(PROJECT, OUT)
sftp.put(local, f'/opt/xnow-flow/static/{OUT}')
sftp.close()
_, o, _ = ssh.exec_command(f"ls -l /opt/xnow-flow/static/{OUT}", timeout=30)
print(o.read().decode('utf-8', 'replace'))
ssh.close()
sz = os.path.getsize(local)
print(f"\n=== ✅ 上传完成 {OUT} ({sz/1024/1024:.1f} MB) ===")
print(f"装机链接: http://192.129.210.52/{OUT}  (nginx root=/opt/xnow-flow/static，无 /ipa/ 前缀)")
