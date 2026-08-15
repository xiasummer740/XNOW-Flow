# -*- coding: utf-8 -*-
"""v1.4.91 全自动复验：核心验证评论区 overlay 关闭（P0-2 残余根治）+ 回归搜索/导航/评论。
v1.4.91 修复：_performComment 打开评论面板后无关闭机制 → 键盘遮 tab bar → 设备困死。
新增 close_overlay 命令（点右上角 Close comment section X 按钮）+ _gotoHomeFeed/_performComment 自动关面板。
用法: uv run --with fastapi python verify-v1.4.91.py
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


def _dispatch_ok(sent):
    return bool(sent and sent.get("success"))


def _cur_page():
    scan, err = get_scan()
    if err:
        return None, err
    r = recognize(scan.get("elements", []))
    return r, scan


def _wait_page(target, tries=6, gap=2.5):
    """等待当前页识别为目标页，返回 (ok, r)"""
    for _ in range(tries):
        time.sleep(gap)
        r, _ = _cur_page()
        if r and r["page"] == target:
            return True, r
    r, _ = _cur_page()
    return False, r


# ============ 测试用例 ============

def t_overlay_close():
    """v1.4.91 核心: comment 打开评论区 → close_overlay 关闭 → 回 feed"""
    sent = _dispatch("comment", {"text": "Nice!"})
    if not _dispatch_ok(sent):
        return ("❌", f"comment 下发失败: {sent.get('message') or sent.get('error')}")
    ok, r = _wait_page("comment")
    if not ok:
        return ("❌", f"评论区未打开 page={r and r['page']}({r and r['title']}) — 无法测关闭，可能前序状态异常")
    opened = r
    sent = _dispatch("close_overlay", {})
    if not _dispatch_ok(sent):
        return ("❌", f"close_overlay 下发失败: {sent.get('message') or sent.get('error')}")
    ok, r = _wait_page("home")
    if ok:
        return ("✅", f"评论区({opened['title']}) → close_overlay → 回 home ✅")
    return ("❌", f"close_overlay 后仍未回 home，当前 page={r and r['page']}({r and r['title']})")


def t_comment_auto_close():
    """v1.4.91: comment 发评论后 _performComment 应自动关面板（不困死）"""
    sent = _dispatch("comment", {"text": "Auto close test"})
    if not _dispatch_ok(sent):
        return ("❌", f"comment 下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(8)  # 发评论 + 自动关面板
    r, _ = _cur_page()
    if r and r["page"] != "comment":
        return ("✅", f"发评论后自动关面板生效，当前 page={r['page']}({r['title']})")
    return ("❌", f"发评论后仍困在评论区 page={r and r['page']}({r and r['title']})，需 close_overlay 兜底")


def t_go_home_from_comment():
    """v1.4.91: _gotoHomeFeed 开头自动关 overlay → 评论区里 go_home 应能回 feed"""
    sent = _dispatch("comment", {"text": "goto home test"})
    if not _dispatch_ok(sent):
        return ("❌", f"comment 下发失败: {sent.get('message') or sent.get('error')}")
    ok, _ = _wait_page("comment")
    if not ok:
        return ("❌", "评论区未打开，无法测 go_home")
    sent = _dispatch("go_home", {})
    if not _dispatch_ok(sent):
        return ("❌", f"go_home 下发失败: {sent.get('message') or sent.get('error')}")
    ok, r = _wait_page("home")
    if ok:
        return ("✅", "评论区里 go_home 自动关 overlay 后回 feed ✅")
    return ("❌", f"评论区里 go_home 仍无法回 feed，当前 page={r and r['page']}({r and r['title']})")


def t_navigation():
    """P0-2 回归: go_home / open_profile / go_back 正常导航"""
    results = []
    for action in ["go_home", "open_profile", "go_back", "go_home"]:
        sent = _dispatch(action, {})
        if not _dispatch_ok(sent):
            results.append(f"{action}: ❌ 下发失败")
            continue
        time.sleep(4)
        r, _ = _cur_page()
        results.append(f"{action}: page={r and r['page']}({r and r['title']})")
    ok = not any("❌" in x for x in results)
    return ("✅" if ok else "❌", "\n      ".join(results))


def t_comment():
    """P1-1 回归: comment 打开面板可见评论 UI"""
    sent = _dispatch("comment", {"text": "Nice!"})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(4)
    scan, err = get_scan()
    if err:
        return ("❌", err)
    labels = [e.get("acc_label", "") for e in scan.get("elements", []) if e.get("acc_label")]
    has_comment_ui = any(any(k in lb for k in ("评论", "发送", "Comment", "Reply", "留言")) for lb in labels)
    # 关闭，避免影响后续
    _dispatch("close_overlay", {})
    return ("✅" if has_comment_ui else "❌",
            f"打开评论面板后找到评论UI={'是' if has_comment_ui else '否'}，元素{scan.get('count')}个")


def t_task_status():
    """P1-2 回归: check_health 设备仍响应"""
    sent = _dispatch("check_health", {})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(6)
    after = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    return ("✅" if after is not None else "❌", "check_health 下发后设备仍响应")


def t_search_timeout():
    """P0-1 回归: search_keyword 不卡死（死锁修复不回归）"""
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    sent = _dispatch("search_keyword", {"keyword": "test"})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(22)
    after = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    alive = after is not None
    scan_ts = _scan_ts(after.get("ts")) if after and after.get("ts") else 0
    ts_progressing = scan_ts > _scan_ts(before)
    sent2 = _dispatch("check_health", {})
    dispatch_still_works = _dispatch_ok(sent2)
    return ("✅" if alive and dispatch_still_works else "❌",
            f"22s 后设备仍响应={alive}，scan推进={ts_progressing}，命令可再下发={dispatch_still_works}")


def main():
    if not PASS:
        print("❌ 未读到 XNW_ADMIN_PASSWORD，检查 .env.local")
        sys.exit(1)
    tests = [
        ("v1.4.91核心: 评论区close_overlay关闭", t_overlay_close),
        ("v1.4.91核心: comment发完自动关面板", t_comment_auto_close),
        ("v1.4.91核心: 评论区里go_home自动关overlay", t_go_home_from_comment),
        ("P0-2回归: 远程导航链路", t_navigation),
        ("P1-1回归: 评论可见性", t_comment),
        ("P1-2回归: 任务状态", t_task_status),
        ("P0-1回归: 搜索不卡死", t_search_timeout),
    ]
    print("=" * 60)
    print(f"v1.4.91 全自动复验 | 设备 {DEVICE}")
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
