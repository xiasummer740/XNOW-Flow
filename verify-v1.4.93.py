# -*- coding: utf-8 -*-
"""v1.4.93 全自动复验（窗口基础回归里程碑）

分层验证：
  L1 基础回归先行 —— 窗口选择正确铁证（扫到 TikTok 主窗口而非浮窗），挂了立即停，不跑功能
  功能复验 —— 修掉 4 个假阳性（导航断言到达 / 任务查真实回填 / tab 必须 int>=0 / 页名走本地识别器）
  截图留证 —— 关键步骤存 PNG 到 verify-artifacts-93/

用法: python -u verify-v1.4.93.py   （需已装 v1.4.93）
"""
import os, sys, json, time, base64, re, datetime, urllib.request, urllib.error

CLOUD = "http://192.129.210.52:8000"
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_0ECF42DC")
POLL_TIMEOUT = 30
PROJECT = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(PROJECT, "verify-artifacts-93")

# 浮窗菜单运营文案黑名单（出现 = 扫到浮窗而非 TikTok UI）
OVERLAY_LABELS = {
    "账号管理", "设置国家", "一键清理所有数据", "关闭服务器链接", "绑定云控后台",
    "自动关注", "采集粉丝", "采集视频", "自动评论点赞", "采集评论数据", "自动发视频",
    "养号", "设备编号", "API ID", "快捷菜单",
}
# TikTok 底部 tab 栏无障碍标识（feed 上应全部出现）
TAB_ANCHORS = {"a11y_vo_home", "a11y_vo_inbox", "a11y_vo_profile", "friends"}


def _load_env():
    env = {}
    p = os.path.join(PROJECT, ".env.local")
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


def _dispatch_ok(sent):
    return bool(sent and sent.get("success"))


def _scan_ts(x):
    try:
        return datetime.datetime.fromisoformat(x.replace("Z", "+00:00")).timestamp()
    except Exception:
        return float(x) if x else 0


# ================= 公共层 =================

def fresh_scan():
    """下发 ui_scan → 等设备上报新 ts，返回 scan dict（GET /ui-scan/ 结构）"""
    before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    sent = _dispatch("ui_scan", {})
    if not _dispatch_ok(sent):
        return None, f"下发失败: {sent.get('message') or sent.get('error')}"
    deadline = time.time() + POLL_TIMEOUT
    scan = None
    while time.time() < deadline:
        time.sleep(1.2)
        scan = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
        if scan and scan.get("has_scan") and _scan_ts(scan.get("ts")) != before:
            return scan, None
    return scan, "手机未上报新 ui_scan"


def recognize_page(scan):
    """本地识别器判页（识别器读 label，设备上报 acc_label → 需映射）"""
    try:
        sys.path.insert(0, os.path.join(PROJECT, "backend"))
        from page_recognizer import recognize
        els = [{**e, "label": e.get("acc_label", "")} for e in scan.get("elements", [])]
        return recognize(els)["page"]
    except Exception:
        return "other"


def control_map():
    try:
        return _api("GET", f"/api/biz/v2/devices/{DEVICE}/control-map/") or {}
    except Exception:
        return {}


def latest_control_page(pages):
    """返回 control-map 中 ts 最新的页（即刚上报的当前页）(name, data)"""
    best_name, best_ts, best = None, "", None
    for name, p in (pages or {}).items():
        ts = p.get("ts") or ""
        if ts >= best_ts:
            best_ts, best_name, best = ts, name, p
    return best_name, best


def tab_of(scan):
    """读最近一次上报页的 tab（int），-1/None = 浮窗根 或 未切成功"""
    cm = control_map()
    _, page = latest_control_page(cm.get("pages") or {})
    if not page:
        return None, None
    try:
        return int(page.get("tab")), page
    except (TypeError, ValueError):
        return None, page


def screen_size(pages):
    for p in (pages or {}).values():
        s = p.get("screen")
        if s and isinstance(s, str) and "x" in s:
            w, _, h = s.partition("x")
            try:
                return (int(w), int(h))
            except ValueError:
                pass
    return (414, 736)


def _parse_frame(frame):
    # 设备上报格式: "{{x, y}, {w, h}}"（逗号后有空格，须容忍）
    m = re.match(r"\{\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}\s*,\s*\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}\}", str(frame or ""))
    if not m:
        return None
    return tuple(float(g) for g in m.groups())


# control-map 页名(设备上报名) ↔ 识别器页名(本地识别名) 映射
CM_PAGE = {"feed": "home", "profile": "profile_mine"}


def assert_page(target, tries=6, gap=2.5):
    """轮询 fresh_scan 直到识别器判为目标页；同时用 control-map 累积全量渲染交叉校验。
    fresh_scan 可能抓到切页首帧/未渲染全的扫描（签名类未出现 → 误判上一页），
    control-map 累积的完整扫描含签名类 → 本地识别器可正确判定。
    仅当目标页条目是 control-map 最新上报页时采信（防陈旧条目误过）。"""
    actual = None
    for _ in range(tries):
        time.sleep(gap)
        scan, err = fresh_scan()
        if err:
            actual = f"err:{err}"
        else:
            actual = recognize_page(scan)
            if actual == target:
                return True, actual
        # 交叉校验：目标页条目为最新上报且元素充分(≥20) → 识别器复核全量渲染
        try:
            cm = control_map()
            pages = cm.get("pages") or {}
            latest_name, _ = latest_control_page(pages)
            cm_key = CM_PAGE.get(target, target)
            entry = pages.get(cm_key)
            if latest_name == cm_key and entry and len(entry.get("elements", [])) >= 20:
                r = recognize_page({"elements": entry["elements"]})
                if r == target:
                    return True, r
        except Exception:
            pass
    return False, actual


def fetch_screenshot(name):
    """下发截图 → 等新 ts → 存 PNG 到 verify-artifacts-93/，返回 (ok, path)"""
    try:
        before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/screenshot/").get("ts")
    except Exception:
        before = None
    sent = _dispatch("screenshot", {})
    if not _dispatch_ok(sent):
        return False, f"下发失败: {sent.get('message') or sent.get('error')}"
    deadline = time.time() + POLL_TIMEOUT
    data = None
    while time.time() < deadline:
        time.sleep(1.5)
        try:
            data = _api("GET", f"/api/biz/v2/devices/{DEVICE}/screenshot/")
        except Exception:
            continue
        if data and data.get("has_screenshot") and data.get("ts") != before:
            break
    if not data or not data.get("has_screenshot") or data.get("ts") == before:
        return False, "手机未上报新截图"
    b64 = data.get("image_base64") or ""
    if not b64:
        return False, "截图为空"
    try:
        png = base64.b64decode(b64)
    except Exception as ex:
        return False, f"base64 解码失败: {ex}"
    os.makedirs(ART, exist_ok=True)
    path = os.path.join(ART, f"{name}.png")
    with open(path, "wb") as f:
        f.write(png)
    return True, path


# ================= L1 基础回归（窗口选择正确铁证）=================

def l1_baseline():
    _dispatch("go_home", {})
    time.sleep(4)
    scan, err = fresh_scan()
    if err:
        return (False, f"L1 前置失败: {err}")
    els = scan.get("elements", [])
    count = scan.get("count", len(els))
    cm = control_map()
    pages = cm.get("pages") or {}
    SW, SH = screen_size(pages)
    det = []

    tab_anchors = sum(1 for e in els
                      if e.get("acc_id") in TAB_ANCHORS or e.get("class") == "TTKTabBarButton")
    det.append(f"tab锚点={tab_anchors}(需≥2)")

    overlay = 0
    for e in els:
        cls = e.get("class") or ""
        if "XNFloatingPanel" in cls or "XNPassThrough" in cls:
            overlay += 1
            continue
        lb = e.get("acc_label") or ""
        if any(k in lb for k in OVERLAY_LABELS):
            overlay += 1
    det.append(f"overlay提示={overlay}(需=0)")

    page = recognize_page(scan)
    det.append(f"识别页={page}(需≠other)")

    in_scr = total_geom = 0
    for e in els:
        r = _parse_frame(e.get("frame"))
        if not r:
            continue
        x, y, w, h = r
        if w <= 0 or h <= 0:
            continue  # 零尺寸布局桩（TTKMusicTagView 等）不计入分母
        total_geom += 1
        if -2 <= x and -2 <= y and x + w <= SW + 2 and y + h <= SH + 2:
            in_scr += 1
    ratio = in_scr / total_geom if total_geom else 0
    det.append(f"屏内比例={ratio:.2f}(需≥0.85) 屏={SW}x{SH} count={count}(需≥20)")

    ok = (count >= 20 and tab_anchors >= 2 and overlay == 0
          and page != "other" and ratio >= 0.85)
    return ok, " | ".join(det)


# ================= 功能复验 =================

def t_tab_switch():
    results = []
    for tab, expect in [("inbox", "inbox"), ("friends", "friends"),
                        ("profile", "profile"), ("home", "feed")]:
        sent = _dispatch("open_tab", {"tab": tab})
        if not _dispatch_ok(sent):
            results.append(f"open_tab {tab}: ❌ 下发失败")
            continue
        ok, page = assert_page(expect, tries=5, gap=2.5)
        tab_idx, _ = tab_of(None)
        good = ok and (tab_idx is not None and tab_idx >= 0)
        results.append(f"open_tab {tab} → 页={page}(期望{expect}) tab={tab_idx} {'✅' if good else '❌'}")
        fetch_screenshot(f"tab_{tab}")
    _dispatch("open_tab", {"tab": "home"})
    time.sleep(3)
    ok_all = not any("❌" in x for x in results)
    return ("✅" if ok_all else "❌", "\n      ".join(results))


def t_comment_open_close():
    """评论区打开(带键盘) → close_overlay → 回 feed（根治 v1.4.91 困死回归）"""
    sent = _dispatch("comment", {"text": "Nice!"})
    if not _dispatch_ok(sent):
        return ("❌", f"comment 下发失败: {sent.get('message') or sent.get('error')}")
    ok, page = assert_page("comment", tries=6, gap=2.5)
    if not ok:
        return ("❌", f"评论区未打开 page={page}")
    fetch_screenshot("comment_open")
    sent = _dispatch("close_overlay", {})
    if not _dispatch_ok(sent):
        return ("❌", f"close_overlay 下发失败: {sent.get('message') or sent.get('error')}")
    ok, page = assert_page("feed", tries=6, gap=2.5)
    if ok:
        fetch_screenshot("comment_closed")
        return ("✅", "评论区 → close_overlay(收键盘+sendActions) → 回 feed ✅")
    return ("❌", f"close_overlay 后未回 feed，当前 page={page}")


def t_control_map_fields():
    scan, err = fresh_scan()
    if err:
        return ("❌", err)
    els = scan.get("elements", [])
    page = recognize_page(scan)
    have_super = sum(1 for e in els if e.get("superclass"))
    have_title = sum(1 for e in els if e.get("title"))
    have_gestures = sum(1 for e in els if e.get("gestures"))
    tab_idx, _ = tab_of(None)
    ok = (scan.get("count", 0) > 0 and page != "other" and have_super > 0
          and have_gestures > 0 and tab_idx is not None and tab_idx >= 0)
    return ("✅" if ok else "❌",
            f"页={page} count={scan.get('count')} superclass={have_super} "
            f"title={have_title} gestures={have_gestures} tab={tab_idx}")


def t_navigation():
    """P0-2 回归：每步断言到达目标页（修假阳性①）"""
    results = []
    for action, expect in [("go_home", "feed"), ("open_profile", "profile"),
                           ("go_back", "feed"), ("go_home", "feed")]:
        sent = _dispatch(action, {})
        if not _dispatch_ok(sent):
            results.append(f"{action}: ❌ 下发失败")
            continue
        ok, page = assert_page(expect, tries=5, gap=2.5)
        results.append(f"{action} → 页={page}(期望{expect}) {'✅' if ok else '❌'}")
    ok_all = not any("❌" in x for x in results)
    return ("✅" if ok_all else "❌", "\n      ".join(results))


def t_comment_visibility():
    sent = _dispatch("comment", {"text": "Nice!"})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(4)
    scan, err = fresh_scan()
    if err:
        return ("❌", err)
    page = recognize_page(scan)
    labels = [e.get("acc_label", "") for e in scan.get("elements", []) if e.get("acc_label")]
    has_ui = any(any(k in lb for k in ("评论", "发送", "Comment", "Reply", "留言")) for lb in labels)
    _dispatch("close_overlay", {})
    return ("✅" if page == "comment" and has_ui else "❌",
            f"页={page} 评论UI={'有' if has_ui else '无'} 元素{scan.get('count')}个")


def t_task_status():
    """任务状态真实回填：创建 check_health 任务 → start → 轮询 status==done（修假阳性②）"""
    body = {
        "type": "check_health",
        "name": "v1.4.93复验-任务回填",
        "device": DEVICE,
        "config": {
            "device_ids": [DEVICE],
            "targets": ["probe"],
            "unit_param": "target",
            "min_interval": 2,
            "params": {},
        },
    }
    try:
        created = _api("POST", "/api/biz/v2/tasks/", body)
    except urllib.error.HTTPError as e:
        return ("❌", f"创建任务失败 HTTP {e.code}: {e.read().decode('utf-8','replace')[:200]}")
    except Exception as ex:
        return ("❌", f"创建任务失败: {ex}")
    tid = created.get("id")
    if not tid:
        return ("❌", f"创建任务无 id: {created}")
    try:
        _api("POST", f"/api/biz/v2/tasks/{tid}/start/", {})
    except Exception as ex:
        return ("❌", f"启动任务失败: {ex}")
    deadline = time.time() + 45
    last = None
    while time.time() < deadline:
        time.sleep(5)
        try:
            data = _api("GET", "/api/biz/v2/tasks/?type=check_health&limit=20")
            for t in (data or {}).get("results", []):
                if t.get("id") == tid:
                    last = t
                    break
        except Exception:
            continue
        if last and last.get("status") in ("done", "failed"):
            break
    if not last:
        return ("❌", f"任务 {tid} 未查询到")
    status = last.get("status")
    ok = status == "done"
    return ("✅" if ok else "❌",
            f"任务#{tid} {last.get('type')} status={status} progress={last.get('progress')} "
            f"log={last.get('last_log')}")


def t_search_not_stuck():
    """P0-1 回归：search_keyword 不卡死（放最后跑）"""
    try:
        before = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/").get("ts")
    except Exception:
        before = None
    sent = _dispatch("search_keyword", {"keyword": "test"})
    if not _dispatch_ok(sent):
        return ("❌", f"下发失败: {sent.get('message') or sent.get('error')}")
    time.sleep(22)
    try:
        after = _api("GET", f"/api/biz/v2/devices/{DEVICE}/ui-scan/")
    except Exception:
        after = None
    alive = after is not None
    sent2 = _dispatch("check_health", {})
    dispatch_still = _dispatch_ok(sent2)
    return ("✅" if alive and dispatch_still else "❌",
            f"22s 后设备响应={alive}，命令可再下发={dispatch_still}")


def main():
    if not PASS:
        print("❌ 未读到 XNW_ADMIN_PASSWORD，检查 .env.local")
        sys.exit(1)
    os.makedirs(ART, exist_ok=True)
    print("=" * 62)
    print(f"v1.4.93 全自动复验 | 设备 {DEVICE} | 分层验证+截图留证")
    print("=" * 62)

    # ---------- 第一层：L1 基础回归先行 ----------
    print("\n--- [L1] 窗口基础回归（扫到 TikTok 主窗口而非浮窗）---")
    ok, msg = l1_baseline()
    shot_ok, shot = fetch_screenshot("l1_baseline")
    print(f"{'✅' if ok else '❌'} {msg}")
    print(f"  截图留证: {'✅ ' + shot if shot_ok else '⚠️ ' + shot}")
    if not ok:
        print("\n❌ L1 基础回归失败 → 停止，不跑功能测试（窗口选错=全部假阳性）")
        print("  先修窗口选择问题，再复验。")
        sys.exit(2)
    print("  ✅ L1 通过 → 进入功能复验")

    # ---------- 第二层：功能复验 ----------
    tests = [
        ("tab切换 setSelectedIndex", t_tab_switch),
        ("评论区 open→close_overlay→feed", t_comment_open_close),
        ("控件地图字段+tab", t_control_map_fields),
        ("P0-2回归: 导航每步断言到达", t_navigation),
        ("P1-1回归: 评论可见性", t_comment_visibility),
        ("P1-2回归: 任务状态真实回填", t_task_status),
        ("P0-1回归: 搜索不卡死(最后)", t_search_not_stuck),
    ]
    results = []
    for name, fn in tests:
        print(f"\n--- {name} ---")
        ok, msg = fn()
        print(f"{ok} {msg}")
        results.append((name, ok, msg))

    # ---------- 收尾：设备回安全态 ----------
    _dispatch("go_home", {})
    _dispatch("close_overlay", {})
    time.sleep(2)

    print("\n" + "=" * 62)
    print("复验汇总")
    print("=" * 62)
    for name, ok, msg in results:
        print(f"{ok} {name}")
    npass = sum(1 for _, ok, _ in results if ok == "✅")
    print(f"\n通过 {npass}/{len(results)}")
    if npass == len(results):
        print("🎉 全部通过 —— v1.4.93 窗口基础回归 + 功能链路验证完成")
    else:
        print("⚠️ 有未通过项 —— 见上方明细 + verify-artifacts-93/ 截图")


if __name__ == "__main__":
    main()
