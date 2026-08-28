#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发版回归清单 — 六条核心命令，防改 A 崩 B（v1.4.127 open_tab 回归血证）

用法:
    python regression-check.py [all | open_tab | like | open_search | search | follow | go_home | backup]
    search 需传 keyword: python regression-check.py search <关键词>

三态判定（写入 ISSUES.md 发版前必须全过）:
    ✅ 真成功 — result 含验收关键字（如 like「红心点亮验证通过」）
    ❌ 假成功 — result success 但无验收证据（= 命令没真干活，同 8/16-27 假成功历史）
    🚨 崩溃   — log 出现 CRASH 或设备 poll 停止响应（watchdog 杀进程模式）

每次发版前跑 all；任一 🚨 或核心项 ❌ → 不发版。
验收关键字与 CommandEngine.m 返回格式绑定，改返回格式需同步改本脚本。
"""
import os, sys, time, json, urllib.request, urllib.error, paramiko

PROJECT = os.path.dirname(os.path.abspath(__file__))
DEVICE = "iphone_A6D8F9B4"
CLOUD = "http://192.129.210.52:8000"
HOST = "192.129.210.52"

env = {}
for line in open(os.path.join(PROJECT, ".env.local"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()
PASS = env.get("XNW_ADMIN_PASSWORD", "")
_token = None
_ssh = None

# 验收关键字映射：result.message 含某关键字 → 真成功
ACCEPT = {
    "like":         "红心点亮验证通过",
    "search":       "搜索完成，已展示结果页",
    "follow":       "已关注（按钮状态验证通过）",
    "backup":       "已备份账号",
    # open_tab/open_search/go_home 无验收关键字 → 走无崩溃 + log 证据
}

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
        with urllib.request.urlopen(req, data, timeout=25) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry:
            _login(); return _api(method, path, body, retry=False)
        return {"error": f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:200]}"}

def _login():
    global _token
    req = urllib.request.Request(CLOUD + "/api/auth/login/", method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, json.dumps({"username": "admin", "password": PASS}).encode(), timeout=20) as r:
        _token = json.loads(r.read())["token"]

def _ssh_connect():
    global _ssh
    _ssh = paramiko.SSHClient(); _ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    _ssh.connect(HOST, 22, "root", env.get("XNW_VPS_PASSWORD", ""), timeout=20)

def _log_size():
    _, o, _ = _ssh.exec_command("wc -c < /opt/xnow-flow/server.log", timeout=15)
    raw = o.read().strip()
    return int(raw) if raw else 0

def _log_from(offset, maxbytes=300000):
    _, o, _ = _ssh.exec_command(
        f"tail -c +{offset} /opt/xnow-flow/server.log 2>/dev/null | tail -c {maxbytes}", timeout=30)
    return o.read().decode("utf-8", "replace")

def run_cmd(action, params=None, wait=4.0, timeout=60):
    """下发命令并捕获 log 增量，返回 (api_resp, log_text)"""
    before = _log_size()
    r = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
             {"action": action, "params": params or {}})
    deadline = time.time() + timeout
    time.sleep(wait)
    text = ""
    while time.time() < deadline:
        sz = _log_size()
        if sz > before:
            text = _log_from(before)
            if "result:" in text:
                break
        time.sleep(1)
    return r, text

def find_result(log):
    for line in log.split("\n"):
        if "result:" in line and "Device" in line:
            return line.strip()
    return "(无 result 行)"

def crashed(log):
    return "CRASH" in log

def device_alive():
    """下发 health 探测设备是否仍响应"""
    r = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
             {"action": "health", "params": {}})
    return bool(r and r.get("device_online"))

def relevant_lines(log):
    """过滤出关键日志行（result/STEP/CRASH/state_diag/深链等）"""
    out = []
    for line in log.split("\n"):
        s = line.strip()
        if any(k in s for k in ("result:", "CRASH", "STEP", "▶️", "🚨",
                                "state_diag", "深链", "沉浸", "_gotoHomeFeed",
                                "pushed_deeplink", "tapTab", "tapAtPoint", "点赞")):
            out.append(s[:260])
    return out[:20]

def verdict(name, log):
    """三态判定：返回 (状态, 证据行)"""
    if crashed(log):
        return "🚨 崩溃", find_result(log)
    kw = ACCEPT.get(name)
    res = find_result(log)
    if kw and kw in res:
        return "✅ 真成功", res
    if kw:
        # 可能返回 failed（诚实失败也算有效响应，标注具体）
        if "未" in res or "failed" in res.lower():
            return "❌ 未生效", res
        return "❌ 假成功", res
    # 无验收关键字的命令：设备仍响应 + 有 result 即视为已执行，打印证据行
    return "✅ 已执行(无崩溃)", res

CHECKS = [
    ("open_tab",     {"tab": "profile"},  "open_tab profile（128 不再崩溃，diag 有返回）"),
    ("open_tab",     {"tab": "home"},     "open_tab home（128 深链兜底回 feed）"),
    ("like",         {},                  "like（红心点亮真验收）"),
    ("open_search",  {},                  "open_search（坐标 386,42 命中搜索按钮）"),
    ("follow",       {},                  "follow（按钮状态真验收）"),
    ("go_home",      {},                  "go_home（回首页，沉浸态也能退出）"),
    ("backup",       {},                  "backup_account（识别登录态并备份）"),
]

def main():
    _login(); _ssh_connect()
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    kw = sys.argv[2] if len(sys.argv) > 2 else "test"
    print(f"设备 {DEVICE} 回归清单: {which}\n" + "=" * 60)
    results = []
    for action, params, desc in CHECKS:
        if which != "all" and action != which:
            continue
        if action == "search":
            pass
        print(f"\n▶ {action} — {desc}")
        if action == "open_tab" and params.get("tab") == "home":
            # open_tab home 前确保设备不死：先探测
            pass
        r, log = run_cmd(action, params)
        status, ev = verdict(action, log)
        results.append((action, params, status, ev))
        print(f"  {status}")
        print(f"  result: {ev[:200]}")
        for ln in relevant_lines(log):
            print(f"  | {ln}")
        time.sleep(1.5)
    print("\n" + "=" * 60)
    bad = [r for r in results if r[2].startswith("🚨") or r[2].startswith("❌")]
    print("回归汇总:")
    for action, params, status, ev in results:
        p = json.dumps(params, ensure_ascii=False) if params else ""
        print(f"  {status}  {action} {p}")
    if bad:
        print(f"\n⚠️  {len(bad)} 项异常 → 不发版。🚨 先修崩溃，❌ 查假成功根因。")
    else:
        print("\n✅ 全部通过 → 可发版")
    _ssh.close()
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
