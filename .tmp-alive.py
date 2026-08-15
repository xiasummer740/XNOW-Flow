# -*- coding: utf-8 -*-
"""实测设备是否活着：下发 ui_scan，看新上报"""
import os, sys, json, time, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_cli import _load_env, _login, _api
DEVICE = "iphone_0ECF42DC"
env = _load_env()
_api.__globals__["CLOUD"] = "http://192.129.210.52:8000"
_api.__globals__["PASS"] = env.get("XNW_ADMIN_PASSWORD","")
def tsnum(x):
    try: return datetime.datetime.fromisoformat(x.replace("Z","+00:00")).timestamp()
    except Exception: return float(x) if x else 0
s0 = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
b0 = tsnum(s0.get("ts")) if s0 else 0
print(f"scan before: ts={s0.get('ts')} count={s0.get('count') if s0 else None}")
r = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/", {"action":"ui_scan","params":{}})
print("dispatch ui_scan:", json.dumps(r, ensure_ascii=False)[:300])
dl = time.time()+30; s1=None
while time.time()<dl:
    time.sleep(1.5)
    s1 = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    if s1 and s1.get("has_scan") and tsnum(s1.get("ts"))!=b0:
        break
if s1 and tsnum(s1.get("ts"))!=b0:
    print(f"✅ 设备活着! 新 scan ts={s1.get('ts')} count={s1.get('count')}")
    labels=[e.get("acc_label","") for e in s1.get("elements",[]) if e.get("acc_label")]
    print("labels:", [l for l in labels if l][:12])
else:
    print(f"❌ 设备未上报新 ui_scan (wait 30s)。last ts={s1.get('ts') if s1 else None}")
