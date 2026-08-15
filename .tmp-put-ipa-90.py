# -*- coding: utf-8 -*-
"""上传 v1.4.90 IPA 到 VPS + 校验 md5 + 确认下载 URL"""
import paramiko, os, hashlib, sys
P = os.path.dirname(os.path.abspath(__file__))
env = {}
with open(os.path.join(P,'.env.local'), encoding='utf-8') as f:
    for line in f:
        line=line.strip()
        if line and not line.startswith('#') and '=' in line:
            k,_,v=line.partition('='); env[k.strip()]=v.strip()
IPA = os.path.join(P, 'TikTok_XNOW_vv1.4.90_BH.ipa')
REMOTE = '/var/www/ipa/TikTok_XNOW_v1.4.90_BH.ipa'
md5 = hashlib.md5(open(IPA,'rb').read()).hexdigest()
print(f"local md5: {md5} ({os.path.getsize(IPA)} bytes)")
ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52',22,'root',env.get('XNW_VPS_PASSWORD',''),timeout=20)
def run(c, t=120):
    _,o,e=ssh.exec_command(c,timeout=t)
    print(o.read().decode('utf-8','replace').strip())
    ec=o.channel.recv_exit_status()
    if ec!=0: print("ERR:", e.read().decode('utf-8','replace').strip())
run("mkdir -p /var/www/ipa", 20)
sftp=ssh.open_sftp()
print("uploading...")
sftp.put(IPA, REMOTE, confirm=True)
sftp.close()
run(f"md5sum {REMOTE}")
run(f"curl -s -o /dev/null -w 'HTTP %{{http_code}} size=%{{size_download}} range=%{{http_code}}' -H 'Range: bytes=0-1023' -r 0-1023 {REMOTE} 2>&1 | tail -1")
ssh.close()
