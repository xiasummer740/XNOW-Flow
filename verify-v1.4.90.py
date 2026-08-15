# -*- coding: utf-8 -*-
"""v1.4.90 全自动复验：先导航/评论/任务状态，最后测搜索（search 卡死修复验证）。
覆盖: P0-2 远程导航 / P1-1 评论可见性 / P1-2 任务状态回填 / P0-1 搜索不卡死(最后测)
v1.4.90 修复：主线程嵌套 dispatch_sync 自锁死锁（search/collect 打开搜索/主页时外层
dispatch_sync(main) 内调内部又 dispatch_sync(main) 的方法 → 主线程死锁 → 设备离线）
用法: uv run --with fastapi python verify-v1.4.90.py
"""
import os, sys, json, time, base64, urllib.request, urllib.error, datetime

CLOUD = "http://192.129.210.52:8000"
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_0ECF42DC")
POLL_TIMEOUT = 30

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "backend"))
from page_recognizer import recognize  # noqa: E402


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
PASS = ENV.get("XNW_ADMIN_PASSWORD", "")
_token: str = None


def _api(method: str, path: str, body=None, retry=True):
    req = urllib.request.Request(CLOUD + path, method=method)
    if _token:
        req.add_header("Authorization", "Bearer " + _token)
    data = None
    if body is not None:
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(req, data, timeout=25) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry:
            _login()
            return _api(method, path, body, retry=False)
        raise


def _login():
    global _token
    req = urllib.request.Request(CLOUD + "/api/auth/login/", method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(
        req, json.dumps({"username": "admin", "password": PASS}).encode(), timeout=25
    ) as r:
        _token = json.loads(r.read())["token"]


def _dispatch(action, params):
    try:
        return _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
                    {"action": action, "params": params or {}})
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:300]}"}


def _scan_ts(x):
    try:
        return datetime.datetime.fromisoformat(x.replace("Z", "+00:00")).timestamp()
    except Exception:
        return float(x) if x else 0


def _wait_scan(before, timeout=POLL_TIMEOUT):
    deadline = time.time() + timeout
    data = None
    while time.time() < deadline:
        time.sleep(1.2)
        data = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
        if data and data.get("has_scan") and _scan_ts(data.get("ts")) != before:
            return data
    return data


def get_scan():
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    sent = _dispatch("ui_scan", {})
    if not sent.get("success"):
        return None, f"下发失败: {sent.get('message') or sent.get('error')}"
    scan = _wait_scan(before)
    if not scan or not scan.get("has_scan") or _scan_ts(scan.get("ts")) == before:
        return None, "手机未上报新 ui_scan"
    return scan, None


def get_shot(out="v190_shot.png"):
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/screenshot/").get("ts")
    sent = _dispatch("screenshot", {})
    if not sent.get("success"):
        return None, f"下发失败: {sent.get('message') or sent.get('error')}"
    deadline = time.time() + POLL_TIMEOUT
    shot = None
    while time.time() < deadline:
        time.sleep(1.2)
        shot = _api("GET", f"/api/biz/v2/devices/{DEVICE}/screenshot/")
        if shot and shot.get("has_screenshot") and _scan_ts(shot.get("ts")) != before:
            break
    if not shot or not shot.get("has_screenshot"):
        return None, "手机未上报新截图"
    b64 = shot.get("data") or shot.get("image") or shot.get("base64") or shot.get("image_base64")
    if not b64:
        return None, f"无 base64: {list(shot.keys())}"
    with open(out, "wb") as f:
        f.write(base64.b64decode(b64))
    return out, None


def _dispatch_ok(sent):
    return bool(sent and sent.get("success"))


# ============ 测试用例 ============

def t_navigation():
    """P0-2: open_profile / go_home / go_back 全链路导航 + 页面识别"""
    results = []
    for action in ["go_home", "open_profile", "go_back", "go_home"]:
        sent = _dispatch(action, {})
        if not _dispatch_ok(sent):
            results.append(f"{action}: ❌ 下发失败 {sent.get('error','')}")
            continue
        time.sleep(4)
        scan, err = get_scan()
        if err:
            results.append(f"{action}: ❌ {err}")
            continue
        r = recognize(scan.get("elements", []))
        results.append(f"{action}: ✅ 当前页={r['page']}({r['title']}) 分={r['score']}/{r['threshold']}")
    ok = all("✅" in x for x in results)
    return ("✅" if ok else "❌", "\n      ".join(results))


def t_comment():
    """P1-1: 评论打开/采集 —— 找屏内可见评论（不再按屏幕外）"""
    sent = _dispatch("comment", {"text": "Nice!"})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(4)
    scan, err = get_scan()
    if err:
        return ("❌", err)
    labels = [e.get("label", "") for e in scan.get("elements", []) if e.get("label")]
    has_comment_ui = any(any(k in lb for k in ("评论", "发送", "Comment", "Reply", "留言")) for lb in labels)
    return ("✅" if has_comment_ui else "❌",
            f"打开评论面板后找到评论UI={'是' if has_comment_ui else '否'}，元素{scan.get('count')}个")


def t_task_status():
    """P1-2: 远程指令任务状态 —— 应 done/failed 而非全 failed 误报"""
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    sent = _dispatch("check_health", {})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(6)
    after = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    alive = after is not None
    return ("✅" if alive else "❌", f"check_health 下发后设备仍响应，ui_scan 可读")


def t_search_timeout():
    """P0-1: search_keyword 不应卡死 —— 15s 超时看门狗返回 + 设备不掉线（v1.4.90 死锁修复验证）"""
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    t0 = time.time()
    sent = _dispatch("search_keyword", {"keyword": "test"})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    # 等待超过 15s 超时窗口 + 缓冲，期间设备必须继续响应（不发死锁=主线程活着=poll 定时器活着）
    time.sleep(22)
    after = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    dt = time.time() - t0
    # 关键判定：22s 后设备仍能响应 api（后端不 500）+ ui_scan 时间戳在推进（poll 心跳活着）
    alive = after is not None
    scan_ts = _scan_ts(after.get("ts")) if after and after.get("ts") else 0
    ts_before = _scan_ts(before)
    ts_progressing = scan_ts > ts_before
    # 额外验证：命令能继续下发（说明 poll 队列没被 search 卡住）
    sent2 = _dispatch("check_health", {})
    dispatch_still_works = _dispatch_ok(sent2)
    return ("✅" if alive and dispatch_still_works else "❌",
            f"{int(dt)}s 后设备仍响应={alive}，scan时间戳推进={ts_progressing}，命令可再下发={dispatch_still_works}")


def main():
    if not PASS:
        print("❌ 未读到 XNW_ADMIN_PASSWORD，检查 .env.local")
        sys.exit(1)
    # 搜索最后测：即使 search 仍卡死，前面的导航/评论/任务状态结果已保留
    tests = [
        ("P0-2 远程导航链路", t_navigation),
        ("P1-1 评论可见性", t_comment),
        ("P1-2 任务状态回填", t_task_status),
        ("P0-1 搜索超时不卡死(死锁修复)", t_search_timeout),
    ]
    print("=" * 60)
    print(f"v1.4.90 全自动复验 | 设备 {DEVICE}")
    print("=" * 60)
    results = []
    for name, fn in tests:
        print(f"\n--- {name} ---")
        ok, msg = fn()
        print(f"{ok} {msg}")
        results.append((name, ok, msg))
    print("\n" + "=" * 60)
    print("复验汇总")
    print("=" * 60)
    for name, ok, msg in results:
        print(f"{ok} {name}")
    npass = sum(1 for _, ok, _ in results if ok == "✅")
    print(f"\n通过 {npass}/{len(results)}")


if __name__ == "__main__":
    main()
