#!/usr/bin/env python3
"""直接 sftp.put 上传 IPA，带 md5 校验"""
import paramiko, os, hashlib
PROJECT = os.path.dirname(os.path.abspath(__file__))
def _load_env():
    env = {}
    with open(os.path.join(PROJECT, '.env.local'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('=')
                env[k.strip()] = v.strip()
    return env
PWD = _load_env().get('XNW_VPS_PASSWORD', '')
local = os.path.join(PROJECT, 'TikTok_XNOW_vv1.4.89_BH.ipa')
remote = '/opt/xnow-flow/static/TikTok_XNOW_v1.4.89_BH.ipa'
local_md5 = hashlib.md5(open(local, 'rb').read()).hexdigest()
print(f"本地 md5={local_md5} ({os.path.getsize(local)/1024/1024:.1f}MB)")
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', PWD, timeout=15)
sftp = ssh.open_sftp()
sftp.put(local, remote, confirm=True)
sftp.close()
# 校验远端 md5
_, out, _ = ssh.exec_command(f"md5sum {remote}")
remote_md5 = out.read().decode().split()[0]
print(f"远端 md5={remote_md5}")
print("✅ 一致" if local_md5 == remote_md5 else "❌ 不一致！")
ssh.close()
