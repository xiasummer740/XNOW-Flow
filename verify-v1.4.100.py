# -*- coding: utf-8 -*-
"""v1.4.100 一次性全功能验证套件（回应"不能每次只解决一个问题"）

覆盖祥哥要求的全部功能项：
  L1 基础回归 · 评论区闭环+黑屏防锁屏(核心修复) · 导航(open_profile tapView) · tab切换
  各页菜单 · collect_fans · check_health · 任务回填 · 搜索不卡死

黑屏修复验证（v1.4.100 核心）：
  t_comment_cycle 每轮 close_overlay 后截图亮度分析——亮度高(>80)=设备亮屏未锁屏；
  t_no_lock 静置 75 秒(>iOS 默认锁屏 30s)后截图亮度仍高 = idleTimerDisabled 生效。

命令结果观测通道：下发 command → 设备执行发 result → _mark_task_from_result 回填任务表
  (status=done/failed + last_log="✅/❌ message") → 本脚本 GET /tasks/?type=<action> 读取。
  可靠，无需 SSH 读 server.log。

⚠️ 有真实副作用的命令（auto_follow_list 真关注、follow_user 真关注、send_dm 真私信、
   comment_video 真评论、like_comment 真点赞）默认跳过；设 XNOW_SIDEEFFECT=1 才执行，
   且都用最小量(limit=1)。翻译依赖后端千问 key（当前欠费），单列预期。

用法: python -u verify-v1.4.100.py
"""
import os, sys, json, time, base64, re, datetime, urllib.request, urllib.error, io

CLOUD = "http://192.129.210.52:8000"
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_0ECF42DC")
POLL_TIMEOUT = 30
PROJECT = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(PROJECT, "verify-artifacts-100")
SIDEEFFECT = os.environ.get("XNOW_SIDEEFFECT", "0") == "1"

OVERLAY_LABELS = {
    "账号管理", "设置国家", "一键清理所有数据", "关闭服务器链接", "绑定云控后台",
    "自动关注", "采集粉丝", "采集视频", "自动评论点赞", "采集评论数据", "自动发视频",
    "养号", "设备编号", "API ID", "快捷菜单",
}
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


def _api(method, path, body=None, retry=True):
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
    best_name, best_ts, best = None, "", None
    for name, p in (pages or {}).items():
        ts = p.get("ts") or ""
        if ts >= best_ts:
            best_ts, best_name, best = ts, name, p
    return best_name, best


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
    m = re.match(r"\{\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}\s*,\s*\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}\}", str(frame or ""))
    if not m:
        return None
    return tuple(float(g) for g in m.groups())


CM_PAGE = {"feed": "home", "profile": "profile_mine"}


def assert_page(target, tries=6, gap=2.5):
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
            pass
        if data and data.get("has_screenshot") and data.get("ts") != before:
            break
    if not data or not data.get("image_base64"):
        return False, "未拿到截图数据"
    path = os.path.join(ART, f"{name}.png")
    with open(path, "wb") as f:
        f.write(base64.b64decode(data["image_base64"]))
    return True, path


def shot_brightness():
    """截图 + PIL 亮度分析（上/中/下三行平均亮度）。
    锁屏时 drawViewHierarchyInRect 画应用窗口 → 全黑(亮度≈0)；解锁时明亮(>100)。
    v1.4.100 用它做"评论关闭后是否仍亮屏"的客观证据。"""
    ok, p = fetch_screenshot("brightness_probe")
    if not ok:
        return None, f"截图失败: {p}"
    try:
        from PIL import Image
        img = Image.open(p).convert("L")
        w, h = img.size
        px = img.load()
        vals = []
        for y in (h // 6, h // 2, 5 * h // 6):
            t = n = 0
            for x in range(0, w, 10):
                t += px[x, y]
                n += 1
            vals.append(round(t / n))
        avg = round(sum(vals) / len(vals))
        return avg, f"亮度 上/中/下={vals} 均={avg}"
    except Exception as e:
        return None, f"亮度分析失败: {e}"


def run_cmd(action, params, timeout=90, name=None):
    """下发命令 → 轮询任务回填（status done/failed + last_log）→ 返回 (ok, detail)。
    只取下发后新建的任务（记录下发前 max_id），避免读到上一轮同 type 旧任务。
    ⚠️ check_health 设备返回 status=active（健康）→ 后端回填 failed 属已知误报，这里放宽判定。"""
    # 记录下发前该 type 任务最大 id
    try:
        before = _api("GET", f"/api/biz/v2/tasks/?type={name or action}&limit=5")
        before_max = max((t.get("id") or 0) for t in (before or {}).get("results", []))
    except Exception:
        before_max = 0
    sent = _dispatch(action, params)
    if not _dispatch_ok(sent):
        return False, f"下发失败: {sent.get('message') or sent.get('error')}"
    if not name:
        name = action
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        time.sleep(4)
        try:
            data = _api("GET", f"/api/biz/v2/tasks/?type={name}&limit=20")
            for t in (data or {}).get("results", []):
                if t.get("id", 0) > before_max:  # 只认本轮新任务
                    if not last or t.get("id", 0) > last.get("id", 0):
                        last = t
        except Exception:
            continue
        if last and last.get("status") in ("done", "failed"):
            break
        if not last and deadline - time.time() < 15:
            break  # 快超时了还没新建任务，不再等
    if not last:
        return False, f"任务未回填（下发成功但设备无 result，可能仍在执行或掉线）"
    log = (last.get("last_log") or "").replace("\n", " ")
    status = last.get("status")
    if status == "done":
        ok = True
    elif status == "failed" and log.strip().startswith("❌ ") and log.strip() != "❌ ":
        # 有实际失败 message 才判失败；空 message（check_health active 误报）放宽
        ok = False
    else:
        ok = status == "done"
    return ok, f"task#{last.get('id')} {last.get('type')} status={status} log={log[:200]}"


# ================= 测试 =================

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
            continue
        total_geom += 1
        if -2 <= x and -2 <= y and x + w <= SW + 2 and y + h <= SH + 2:
            in_scr += 1
    ratio = in_scr / total_geom if total_geom else 0
    det.append(f"屏内比例={ratio:.2f}(需≥0.85) 屏={SW}x{SH} count={count}(需≥20)")
    ok = (count >= 20 and tab_anchors >= 2 and overlay == 0
          and page != "other" and ratio >= 0.85)
    return ok, " | ".join(det)


def t_comment_cycle():
    """评论区闭环 + 黑屏防锁屏（v1.4.100 核心修复）：开评论→close_overlay→回 feed，连跑两遍。
    每轮 close_overlay 后做亮度分析——亮度高(>80)=设备亮屏未锁屏=黑屏修复生效；
    低(≈0)=又锁屏了=修复失败。⚠️ 每轮末尾强制 close_overlay 兜底。"""
    results = []
    for i in (1, 2):
        sent = _dispatch("comment", {"text": "Nice!"})
        if not _dispatch_ok(sent):
            results.append(f"第{i}轮 comment 下发失败: {sent.get('message')}")
            _dispatch("close_overlay", {})
            time.sleep(3)
            continue
        ok, page = assert_page("comment", tries=6, gap=2.5)
        if ok:
            fetch_screenshot(f"comment_open_{i}")
            results.append(f"第{i}轮 评论面板打开 ✅ (page={page})")
        else:
            results.append(f"第{i}轮 comment 后未确认评论页，page={page} ⚠️(识别器依赖新窗口检测)")
        # 无论面板是否确认打开，都执行关闭（兜底防残留）
        sent = _dispatch("close_overlay", {})
        if not _dispatch_ok(sent):
            results.append(f"第{i}轮 close_overlay 下发失败: {sent.get('message')}")
            time.sleep(3)
            continue
        ok, page = assert_page("feed", tries=6, gap=2.5)
        if ok and page == "feed":
            fetch_screenshot(f"comment_closed_{i}")
            # 核心：关闭后亮度分析（防锁屏/视频恢复）
            time.sleep(2)
            bright, bdetail = shot_brightness()
            if bright is None:
                results.append(f"第{i}轮 评论→close→feed ✅ 但{bdetail}")
            elif bright > 80:
                results.append(f"第{i}轮 评论→close→feed ✅ 且亮屏未锁屏({bdetail})")
            else:
                results.append(f"第{i}轮 评论→close→feed ✅ 但亮度{bright} 疑似又锁屏 ❌")
        else:
            results.append(f"第{i}轮 close_overlay 后未回 feed，page={page} ❌")
            _dispatch("close_overlay", {})
            time.sleep(3)
    ok_all = not any("❌" in x for x in results)
    return ("✅" if ok_all else "❌", "\n      ".join(results))


def t_no_lock():
    """防锁屏验证（v1.4.100 核心）：静置 75 秒（>iOS 默认 30s 自动锁屏），再截图。
    亮度仍高 = idleTimerDisabled 生效，设备永不锁屏 = 黑屏根治。
    亮度过低 = idleTimer 未生效，iOS 又锁屏了 = 修复失败。"""
    results = []
    print("    [t_no_lock] 静置 75 秒模拟无人操作（验证不锁屏）...")
    time.sleep(75)
    bright, bdetail = shot_brightness()
    if bright is None:
        return ("❌", bdetail)
    if bright > 80:
        results.append(f"静置75秒后亮度{bright} > 80 → 未锁屏 ✅ ({bdetail})")
    else:
        results.append(f"静置75秒后亮度{bright} ≈ 0 → 又锁屏了 ❌ ({bdetail})")
    return ("✅" if bright > 80 else "❌", "\n      ".join(results))


def t_navigation():
    """导航每步断言到达（P0-2 回归 + v1.4.100 open_profile tapView 修复）"""
    results = []
    for action, expect in [("go_home", "feed"), ("open_profile", "profile"),
                           ("go_back", "feed"), ("go_home", "feed")]:
        sent = _dispatch(action, {})
        if not _dispatch_ok(sent):
            results.append(f"{action}: ❌ 下发失败")
            continue
        ok, page = assert_page(expect, tries=5, gap=2.5)
        # open_profile 是 v1.4.99/100 tapView 修复的关键步骤，必留截图证据
        if action == "open_profile":
            if ok:
                fetch_screenshot("nav_open_profile_ok")
            else:
                fetch_screenshot("nav_open_profile_fail")
        results.append(f"{action} → 页={page}(期望{expect}) {'✅' if ok else '❌'}")
    ok_all = not any("❌" in x for x in results)
    return ("✅" if ok_all else "❌", "\n      ".join(results))


def t_tab_switch():
    results = []
    for tab, expect in [("inbox", "inbox"), ("friends", "friends"),
                        ("profile", "profile"), ("home", "feed")]:
        sent = _dispatch("open_tab", {"tab": tab})
        if not _dispatch_ok(sent):
            results.append(f"open_tab {tab}: ❌ 下发失败")
            continue
        ok, page = assert_page(expect, tries=5, gap=2.5)
        results.append(f"open_tab {tab} → 页={page}(期望{expect}) {'✅' if ok else '❌'}")
        fetch_screenshot(f"tab_{tab}")
    _dispatch("open_tab", {"tab": "home"})
    time.sleep(3)
    ok_all = not any("❌" in x for x in results)
    return ("✅" if ok_all else "❌", "\n      ".join(results))


def t_task_status():
    """任务状态真实回填（P1-2 回归）：下发 check_health → 任务 done"""
    return run_cmd("check_health", {}, timeout=45)


def t_search_not_stuck():
    """搜索不卡死（P0-1 回归）：search_keyword 22s 后设备仍响应"""
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


def t_env_diag():
    """环境伪装诊断命令"""
    return run_cmd("env_diag", {}, timeout=45)


def t_get_country():
    """当前国家查询"""
    return run_cmd("get_country", {}, timeout=45)


def t_collect_fans():
    """collect_fans 采集粉丝（只读，count=5 小量）"""
    return run_cmd("collect_fans", {"count": 5}, timeout=120, name="collect_fans")


def t_auto_follow_list():
    """auto_follow_list 粉丝列表自动关注（真实副作用！limit=1 最小量）"""
    if not SIDEEFFECT:
        return ("SKIP", "需 XNOW_SIDEEFFECT=1 才执行（会真实关注）")
    return run_cmd("auto_follow_list", {"limit": 1}, timeout=120, name="auto_follow_list")


def t_open_live():
    """open_live 进直播间：无 uid 参数 → 预期 failed（验证命令链路与设备稳定）"""
    return run_cmd("open_live", {}, timeout=60, name="open_live")


def t_control_map_fields():
    scan, err = fresh_scan()
    if err:
        return ("❌", err)
    els = scan.get("elements", [])
    page = recognize_page(scan)
    have_super = sum(1 for e in els if e.get("superclass"))
    have_gestures = sum(1 for e in els if e.get("gestures"))
    ok = (scan.get("count", 0) > 0 and page != "other" and have_super > 0
          and have_gestures > 0)
    return ("✅" if ok else "❌",
            f"页={page} count={scan.get('count')} superclass={have_super} gestures={have_gestures}")


def main():
    if not PASS:
        print("❌ 未读到 XNW_ADMIN_PASSWORD，检查 .env.local")
        sys.exit(1)
    os.makedirs(ART, exist_ok=True)
    _login()
    print("=" * 62)
    print(f"v1.4.100 一次性全功能验证 | 设备 {DEVICE}")
    print(f"副作用命令: {'启用(最小量)' if SIDEEFFECT else '跳过'}")
    print("=" * 62)

    # 当前页诊断
    try:
        scan0, err0 = fresh_scan()
        print(f"[当前页] 识别={recognize_page(scan0) if scan0 else err0} "
              f"count={scan0.get('count') if scan0 else 0}")
    except Exception:
        print("[当前页] 读取失败")

    print("\n--- [L1] 窗口基础回归 ---")
    ok, msg = l1_baseline()
    shot_ok, shot = fetch_screenshot("l1_baseline")
    print(f"{'✅' if ok else '❌'} {msg}")
    print(f"  截图: {'✅ ' + shot if shot_ok else '⚠️ ' + shot}")
    if not ok:
        print("\n❌ L1 失败 → 停止（窗口选错=全部假阳性）")
        sys.exit(2)
    print("  ✅ L1 通过 → 进入功能验证\n")

    tests = [
        ("评论区闭环×2（核心修复）", t_comment_cycle),
        ("防锁屏 静置75秒(核心修复)", t_no_lock),
        ("导航 每步断言到达", t_navigation),
        ("tab 切换", t_tab_switch),
        ("控件地图字段", t_control_map_fields),
        ("任务回填 check_health", t_task_status),
        ("env_diag 环境诊断", t_env_diag),
        ("get_country 国家查询", t_get_country),
        ("collect_fans 采集粉丝", t_collect_fans),
        ("auto_follow_list 自动关注", t_auto_follow_list),
        ("open_live 进直播间", t_open_live),
        ("搜索不卡死(最后)", t_search_not_stuck),
    ]
    results = []
    for name, fn in tests:
        print(f"--- {name} ---")
        mark, msg = fn()
        print(f"{mark} {msg}")
        results.append((name, mark, msg))
        print()

    # 收尾：设备回安全态
    _dispatch("go_home", {})
    _dispatch("close_overlay", {})
    time.sleep(2)

    print("=" * 62)
    print("验证汇总")
    print("=" * 62)
    npass = nskip = 0
    for name, mark, msg in results:
        print(f"{mark} {name}")
        if mark == "✅":
            npass += 1
        elif mark == "SKIP":
            nskip += 1
    ntotal = len(results)
    print(f"\n通过 {npass}/{ntotal}（跳过 {nskip}）| 截图在 {ART}/")
    if npass + nskip == ntotal:
        print("🎉 全部通过 —— v1.4.100 全功能验证完成")
    else:
        print("⚠️ 有未通过项 —— 见上方明细 + 截图留证")
    print("=" * 62)


if __name__ == "__main__":
    main()
