# -*- coding: utf-8 -*-
"""查设备在线状态 + ui-scan 时间戳"""
import os, sys, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_cli import _load_env, _login, _api
DEVICE = "iphone_0ECF42DC"
env = _load_env()
_api.__globals__["CLOUD"] = "http://192.129.210.52:8000"
_api.__globals__["PASS"] = env.get("XNW_ADMIN_PASSWORD","")
def dump(name, data):
    print(f"\n[{name}]")
    print(json.dumps(data, ensure_ascii=False, default=str)[:800])
for path in [f"/api/biz/v2/devices/device-bindings/{DEVICE}/",
             f"/api/v2/devices/device-bindings/{DEVICE}/",
             "/api/biz/v2/devices/device-bindings/"]:
    try:
        dump("BINDINGS "+path, _api("GET", path))
        break
    except Exception as e:
        print(f"{path} err: {e}")
s = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
if s and s.get("ts"):
    ts = s["ts"]
    print("\nSCAN ts:", ts, "| age:", int(time.time()-ts), "s | count:", s.get("count"))
# 试在线列表
try:
    dump("ONLINE", _api("GET", "/api/biz/v2/devices/online/"))
except Exception as e:
    print("online err:", e)
