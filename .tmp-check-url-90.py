# -*- coding: utf-8 -*-
"""把 v1.4.90 放到正确位置 + 验证下载 URL"""
import paramiko, os
P = os.path.dirname(os.path.abspath(__file__))
env = {}
with open(os.path.join(P,'.env.local'), encoding='utf-8') as f:
    for line in f:
        line=line.strip()
        if line and not line.startswith('#') and '=' in line:
            k,_,v=line.partition('='); env[k.strip()]=v.strip()
ssh=paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52',22,'root',env.get('XNW_VPS_PASSWORD',''),timeout=15)
def run(c):
    _,o,e=ssh.exec_command(c,timeout=30)
    print(o.read().decode('utf-8','replace').strip())
run("sed -n '1,30p' /etc/nginx/sites-enabled/xnow-https")
run("cp /var/www/ipa/TikTok_XNOW_v1.4.90_BH.ipa /opt/xnow-flow/static/ && ls -la /opt/xnow-flow/static/ | grep 1.4.90")
run("curl -skI https://127.0.0.1/TikTok_XNOW_v1.4.90_BH.ipa | head -6")
ssh.close()
