# -*- coding: utf-8 -*-
"""上传 v1.4.101 IPA 到 VPS + 校验 md5 + 确认下载 URL"""
import paramiko, os, hashlib
P = os.path.dirname(os.path.abspath(__file__))
env = {}
with open(os.path.join(P, '.env.local'), encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, _, v = line.partition('='); env[k.strip()] = v.strip()
VER = '1.4.101'
IPA = os.path.join(P, f'TikTok_XNOW_v{VER}_BH.ipa')
REMOTE = f'/var/www/ipa/TikTok_XNOW_v{VER}_BH.ipa'
md5 = hashlib.md5(open(IPA, 'rb').read()).hexdigest()
print(f"local md5: {md5} ({os.path.getsize(IPA)} bytes)")
ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', env.get('XNW_VPS_PASSWORD', ''), timeout=20)
def run(c, t=180):
    _, o, e = ssh.exec_command(c, timeout=t)
    print(o.read().decode('utf-8', 'replace').strip())
    ec = o.channel.recv_exit_status()
    if ec != 0: print("ERR:", e.read().decode('utf-8', 'replace').strip())
run("mkdir -p /var/www/ipa", 20)
sftp = ssh.open_sftp()
print("uploading (374MB)...")
sftp.put(IPA, REMOTE, confirm=True)
sftp.close()
run(f"md5sum {REMOTE}")
ssh.close()
print(f"URL: http://192.129.210.52/ipa/TikTok_XNOW_v{VER}_BH.ipa")
