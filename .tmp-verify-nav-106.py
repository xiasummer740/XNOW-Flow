# -*- coding: utf-8 -*-
"""v1.4.106 open_tab home 修复真机验证：
1) 依次 open_tab friends→home→inbox→home→profile→home
2) 每条 open_tab 后从 server.log 抓最新 result 里的 diag（应见 home_syncReject_deeplink 或 home_setIndex）
3) vc_scan 确认 selectedIndex 实际落位 0
"""
import os, json, time, urllib.request, paramiko, re

CLOUD = "http://192.129.210.52:8000"
DEVICE = "iphone_0ECF42DC"
P = os.path.dirname(os.path.abspath(__file__))
env = {}
with open(os.path.join(P, '.env.local'), encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, _, v = line.partition('='); env[k.strip()] = v.strip()
PASS = env.get('XNW_ADMIN_PASSWORD', '')
VPS_PWD = env.get('XNW_VPS_PASSWORD', '')
req = urllib.request.Request(CLOUD + '/api/auth/login/', method='POST')
req.add_header('Content-Type', 'application/json')
tok = json.loads(urllib.request.urlopen(req, json.dumps({'username':'admin','password':PASS}).encode(), timeout=25).read())['token']
def api(m, p, b=None):
    r = urllib.request.Request(CLOUD + p, method=m)
    r.add_header('Authorization', 'Bearer ' + tok)
    data = None
    if b is not None:
        r.add_header('Content-Type', 'application/json'); data = json.dumps(b).encode()
    with urllib.request.urlopen(r, data, timeout=25) as resp:
        return json.loads(resp.read())

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', VPS_PWD, timeout=15)
def srun(cmd, t=30):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=t)
    ec = stdout.channel.recv_exit_status()
    return stdout.read().decode('utf-8', errors='replace') + stderr.read().decode('utf-8', errors='replace')

def last_open_tab_diag():
    """抓最近一条 open_tab result 的 diag（v1.4.106 起 result 含 tab+diag）"""
    out = srun("grep 'result:.*open_tab' /opt/xnow-flow/server.log | tail -1")
    m = re.search(r"diag': \{([^}]*)\}", out)
    if not m:
        return out[out.find('result:')+7:][:150]
    return m.group(1)

def last_vc_scan():
    out = srun("grep 'action.*vc_scan' /opt/xnow-flow/server.log | tail -1")
    m = re.search(r"selectedIndex': (\d+)", out)
    return int(m.group(1)) if m else '?'

print("=== v1.4.106 open_tab home 修复验证 ===")
ok = True
for tab in ['friends', 'home', 'inbox', 'home', 'profile', 'home']:
    api('POST', f'/api/biz/v2/devices/{DEVICE}/command/', {'action':'open_tab','params':{'tab':tab}})
    time.sleep(3)
    diag = last_open_tab_diag()
    api('POST', f'/api/biz/v2/devices/{DEVICE}/command/', {'action':'vc_scan','params':{}})
    time.sleep(3)
    sel = last_vc_scan()
    mark = '✅' if (tab != 'home' or sel == 0) else '❌'
    if tab == 'home' and sel != 0: ok = False
    print(f"open_tab {tab:8s} → diag[{diag}]  vc_scan selectedIndex={sel}  {mark}")
print("=== " + ("全部通过 ✅" if ok else "有失败 ❌") + " ===")
ssh.close()
