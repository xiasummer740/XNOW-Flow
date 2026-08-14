# -*- coding: utf-8 -*-
"""拉取云端缓存的原始 ui_scan 数据存为 JSON 档案（供离线交叉验证）。用法:
    uv run --with fastapi python fetch_scan.py <输出文件名>
"""
import os, sys, json, urllib.request, urllib.error

CLOUD = "http://192.129.210.52:8000"
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_0ECF42DC")


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


def _login() -> str:
    req = urllib.request.Request(CLOUD + "/api/auth/login/", method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(
        req, json.dumps({"username": USER, "password": PASS}).encode(), timeout=15
    ) as r:
        return json.loads(r.read())["token"]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "live_scan6.json"
    tok = _login()
    req = urllib.request.Request(CLOUD + f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    req.add_header("Authorization", "Bearer " + tok)
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.loads(r.read())
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"saved {out}: ts={data.get('ts')} elements={len(data.get('elements', []))}")


if __name__ == "__main__":
    main()
