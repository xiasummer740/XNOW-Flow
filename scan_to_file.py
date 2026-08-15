# -*- coding: utf-8 -*-
"""触发手机 ui_scan → 等待上报 → 保存原始 elements 到 JSON（供离线分析）。
用法:
    python scan_to_file.py <输出文件名.json>
"""
import os, sys, time, json, urllib.request, urllib.error

CLOUD = "http://192.129.210.52:8000"
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_0ECF42DC")
POLL_TIMEOUT = 15


def _load_env() -> dict:
    env = {}
    p = os.path.join(os.path.dirname(__file__), ".env.local")
    with open(p, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip()
    return env


ENV = _load_env()
USER = "admin"
PASS = ENV.get("XNW_ADMIN_PASSWORD", "")
_token = None


def _api(method, path, body=None, retry=True):
    global _token
    req = urllib.request.Request(CLOUD + path, method=method)
    if _token:
        req.add_header("Authorization", "Bearer " + _token)
    data = None
    if body is not None:
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(req, data, timeout=15) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry:
            _token = None
            _login()
            return _api(method, path, body, retry=False)
        raise


def _login():
    global _token
    req = urllib.request.Request(CLOUD + "/api/auth/login/", method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(
        req, json.dumps({"username": USER, "password": PASS}).encode(), timeout=15
    ) as r:
        _token = json.loads(r.read())["token"]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "scan.json"
    if not _token:
        _login()
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    sent = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
                {"action": "ui_scan", "params": {}})
    if not sent.get("success"):
        print(f"❌ 下发失败: {sent.get('message')}")
        return 1
    scan = None
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        time.sleep(1.0)
        scan = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
        if scan.get("has_scan") and scan.get("ts") != before:
            break
    if not scan or not scan.get("has_scan") or scan.get("ts") == before:
        print("❌ 手机未上报扫描（可能不在线或页面切换中）")
        return 1
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"ts": scan.get("ts"), "count": scan.get("count"),
                   "elements": scan.get("elements", [])}, f, ensure_ascii=False)
    print(f"✅ 已存档 {out}: ts={scan.get('ts')} count={scan.get('count')}")


if __name__ == "__main__":
    sys.exit(main())
