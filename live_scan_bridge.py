# -*- coding: utf-8 -*-
"""手机当前页实时识别桥接服务（本机 8091）。
浏览器按钮 → 触发云端手机 ui_scan → 读缓存 → 识别 → 显示。
凭证从 .env.local 读取，不暴露给浏览器。运行:
    cd F:/summer/vs-code/XNOW-Flow && python live_scan_bridge.py
"""
import os
import json
import sys
import time
import urllib.request
import urllib.error
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "backend"))
from page_recognizer import recognize

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import uvicorn

# ---------- 配置 ----------
CLOUD = "http://192.129.210.52:8000"
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_0ECF42DC")
POLL_TIMEOUT = 12  # 最多等手机 12 秒


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
_token: Optional[str] = None


def _api(method: str, path: str, body=None, retry=True) -> dict:
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


app = FastAPI(title="手机当前页识别")


@app.get("/", response_class=HTMLResponse)
def index():
    with open(os.path.join(os.path.dirname(__file__), "live_scan.html"), encoding="utf-8") as f:
        return f.read()


@app.post("/api/scan")
def do_scan():
    """触发手机 ui_scan → 等待上报 → 识别当前页。"""
    if not _token:
        _login()
    # 记录扫描前的缓存时间戳，命令生效后缓存会刷新
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    try:
        sent = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
                    {"action": "ui_scan", "params": {}})
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"下发命令失败 HTTP {e.code}"}
    if not sent.get("success"):
        return {"ok": False, "error": sent.get("message", "下发失败")}
    # 轮询直到手机上报了新数据
    deadline = time.time() + POLL_TIMEOUT
    scan = None
    while time.time() < deadline:
        time.sleep(1.0)
        scan = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
        if scan.get("has_scan") and scan.get("ts") != before:
            break
    if not scan or not scan.get("has_scan") or scan.get("ts") == before:
        return {"ok": False, "error": "手机没有上报扫描结果（可能不在线或未执行）"}
    res = recognize(scan.get("elements", []))
    res["ok"] = True
    res["device"] = DEVICE
    res["ts"] = scan.get("ts")
    res["total"] = scan.get("count")
    return res


@app.post("/api/screenshot")
def do_screenshot():
    """触发手机截图 → 等待上报 → 返回 base64 图。"""
    if not _token:
        _login()
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/screenshot/").get("ts")
    try:
        sent = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
                    {"action": "screenshot", "params": {}})
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"下发命令失败 HTTP {e.code}"}
    if not sent.get("success"):
        return {"ok": False, "error": sent.get("message", "下发失败")}
    deadline = time.time() + POLL_TIMEOUT
    shot = None
    while time.time() < deadline:
        time.sleep(1.0)
        shot = _api("GET", f"/api/biz/v2/devices/{DEVICE}/screenshot/")
        if shot.get("has_screenshot") and shot.get("ts") != before:
            break
    if not shot or not shot.get("has_screenshot") or shot.get("ts") == before:
        return {"ok": False, "error": "手机没有上报截图（可能不在线或未执行）"}
    shot["ok"] = True
    shot["device"] = DEVICE
    return shot


if __name__ == "__main__":
    if not PASS:
        print("❌ 未读到 XNW_ADMIN_PASSWORD，检查 .env.local")
        sys.exit(1)
    print(f"桥接服务启动: http://127.0.0.1:8091  (设备 {DEVICE})")
    uvicorn.run(app, host="127.0.0.1", port=8091, log_level="warning")
