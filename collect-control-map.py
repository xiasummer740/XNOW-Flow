#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TikTok 控件基线地图采集器 — 根治"每次现场猜锚点，TikTok 更新就退化"

用法:
    python collect-control-map.py <页面标签> [wait] [timeout]

    <页面标签> 如 feed / search / profile / following / comment / edit_profile
    数据源: 下发 ui_scan 命令 → SSH 读 server.log 增量行解析控件
    输出:
        docs/control-map/<页面标签>.json   结构化数据(类名/坐标/frame/accId/label)
        docs/control-map/<页面标签>.md     可读对照表
        docs/control-map/index.md          地图索引

流程:
    1. 设备导航到目标页面(人工/命令)
    2. 本脚本下发 ui_scan 采集该页全部控件
    3. 数据固化进 docs/control-map/ → 之后修控件先查表，不现场猜
TikTok 更新后: 重新采集同页面 → diff 对照旧基线，一眼看出锚点漂移
"""
import os, re, sys, json, time, urllib.request, urllib.error, paramiko

PROJECT = os.path.dirname(os.path.abspath(__file__))
DEVICE = "iphone_A6D8F9B4"
CLOUD = "http://192.129.210.52:8000"
HOST = "192.129.210.52"
OUTDIR = os.path.join(PROJECT, "docs", "control-map")

env = {}
for line in open(os.path.join(PROJECT, ".env.local"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()
PASS = env.get("XNW_ADMIN_PASSWORD", "")
_token = None
_ssh = None

UI_RE = re.compile(
    r"UI \[([^\]]+)\] x=([\d.]+) y=([\d.]+) frame=\{\{([^}]*)\}, \{([^}]*)\}\} "
    r"acc_id=([^ ]*) acc_label=(.*?) sel=(\w+)"
)


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


def collect(page, wait=4.0, timeout=60):
    """下发 ui_scan 并解析控件"""
    os.makedirs(OUTDIR, exist_ok=True)
    before = _log_size()
    r = _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
             {"action": "ui_scan", "params": {}})
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
    # 收集 UI 行
    controls = []
    for line in text.split("\n"):
        m = UI_RE.search(line)
        if m:
            cls, x, y, f1, f2, acc_id, label, sel = m.groups()
            controls.append({
                "class": cls,
                "x": round(float(x)), "y": round(float(y)),
                "frame": f"{{{f1}}}, {{{f2}}}",
                "accId": acc_id,
                "label": label,
                "selected": sel,
            })
    # 排序: y 再 x（同屏幕从上到下）
    controls.sort(key=lambda c: (c["y"], c["x"]))
    # 去重(同 class+accId+坐标 10px 内)
    deduped, seen = [], []
    for c in controls:
        key = (c["class"], c["accId"])
        dup = any(abs(c["x"] - s["x"]) <= 10 and abs(c["y"] - s["y"]) <= 10
                  and s["class"] == c["class"] and s["accId"] == c["accId"] for s in seen)
        if not dup:
            deduped.append(c); seen.append(c)
    if not deduped:
        print("⚠️  未解析到控件行。可能 ui_scan 未完成或 log 读取失败，最后 2000 字符：")
        print(text[-2000:])
        return None
    # 落盘
    json_path = os.path.join(OUTDIR, f"{page}.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"page": page, "device": DEVICE,
                   "captured": time.strftime("%Y-%m-%d %H:%M:%S"),
                   "count": len(deduped), "controls": deduped}, f,
                  ensure_ascii=False, indent=1)
    write_md(page, deduped)
    write_index()
    print(f"✅ 采集完成 {page}: {len(deduped)} 控件 → {json_path}")
    return deduped


def write_md(page, controls):
    lines = [f"# 控件基线地图: {page}", "",
             f"> 采集 {time.strftime('%Y-%m-%d %H:%M:%S')} | 设备 {DEVICE} | {len(controls)} 控件",
             "> 用途: 修控件先查此表，不现场猜。TikTok 更新后重采 diff 对照。", "",
             "| 类名 | accId | x,y | frame | label | 选中 |",
             "|------|-------|-----|-------|-------|-----|"]
    for c in controls:
        label = c["label"].replace("|", "\\|") if c["label"] else ""
        lines.append(f"| `{c['class']}` | `{c['accId']}` | {c['x']},{c['y']} | `{c['frame']}` | {label} | {c['selected']} |")
    with open(os.path.join(OUTDIR, f"{page}.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_index():
    files = sorted(f for f in os.listdir(OUTDIR) if f.endswith(".json"))
    lines = ["# TikTok 控件基线地图索引", "",
             "> 根治「锚点靠猜」：每个关键页面的控件(类名/accId/坐标/label)固化在此，" ,
             "> 修控件先查表；TikTok 更新后重采对照 diff，锚点漂移一眼看出。", ""]
    for f in files:
        d = json.load(open(os.path.join(OUTDIR, f), encoding="utf-8"))
        lines.append(f"- [{d['page']}]({f[:-5]}.md) — {d['count']} 控件（{d['captured']}）")
    lines += ["", "## 采集方法", "```bash",
              "# 1. 导航设备到目标页面", "# 2. 采集",
              "python collect-control-map.py <页面标签>", "```"]
    with open(os.path.join(OUTDIR, "index.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    _login(); _ssh_connect()
    page = sys.argv[1] if len(sys.argv) > 1 else "current"
    wait = float(sys.argv[2]) if len(sys.argv) > 2 else 4.0
    timeout = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    collect(page, wait, timeout)
    _ssh.close()
