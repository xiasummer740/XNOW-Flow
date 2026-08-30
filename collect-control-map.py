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
DEVICE = os.environ.get("XNOW_DEVICE", "iphone_A8DE7E93")
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
    r"UI \[([^\]]+)\] x=(-?[\d.]+) y=(-?[\d.]+) frame=\{\{([^}]*)\}, \{([^}]*)\}\} "
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


def _scan_once(timeout=60):
    """下发 ui_scan 并解析控件（单次快照）。返回去重后的 controls 列表。"""
    os.makedirs(OUTDIR, exist_ok=True)
    before = _log_size()
    _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
         {"action": "ui_scan", "params": {}})
    deadline = time.time() + timeout
    time.sleep(4.0)
    text = ""
    got_result = got_summary = False
    last_sz = 0
    while time.time() < deadline:
        sz = _log_size()
        if sz > before:
            cur = _log_from(before)
            # ui_scan 元素行在 result 之后才上报（result → "ui_scan: N elements" → UI 行）
            if "ui_scan: " in cur and " elements" in cur:
                got_summary = True
            if "result:" in cur:
                got_result = True
            text = cur
            # 已收到元素上报/结果 且 日志停止增长 = UI 行全部落地
            if (got_summary or got_result) and sz == last_sz:
                break
            last_sz = sz
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
        dup = any(abs(c["x"] - s["x"]) <= 10 and abs(c["y"] - s["y"]) <= 10
                  and s["class"] == c["class"] and s["accId"] == c["accId"] for s in seen)
        if not dup:
            deduped.append(c); seen.append(c)
    if not deduped:
        print("⚠️  未解析到控件行。可能 ui_scan 未完成或 log 读取失败，最后 2000 字符：")
        print(text[-2000:])
        return None
    return deduped


def collect(page, wait=4.0, timeout=60):
    """下发 ui_scan 并解析控件（单页单次采集）"""
    deduped = _scan_once(timeout)
    if deduped is None:
        return None
    _save(page, deduped)
    print(f"✅ 采集完成 {page}: {len(deduped)} 控件 → {os.path.join(OUTDIR, page + '.json')}")
    return deduped


def collect_scroll(page, scrolls=6, timeout=60):
    """滚动采集：scan → scroll_down → 再 scan → 合并，覆盖滚动加载的控件。

    合并策略：按 (class, accId, label) 归并 —— 列表行模板（同 class+accId）重复出现
    记为多实例；新 label（滚动加载出的新行内容）也纳入。输出「控件类型 + 实例数 +
    首次出现位置」，反应整页滚动范围的控件结构。
    """
    master = {}            # (class, accId) -> merged（列表行模板归并）
    order = []             # 保持首次出现顺序
    scans = []
    for i in range(scrolls):
        controls = _scan_once(timeout)
        if controls is None:
            break
        scans.append(controls)
        fresh = 0
        for c in controls:
            key = (c["class"], c["accId"])
            if key in master:
                m = master[key]
                m["count"] += 1
                # label 记出现最多的（模板 label = 多数行共享的文案）
                m["_label_cnt"][c["label"]] = m["_label_cnt"].get(c["label"], 0) + 1
            else:
                master[key] = {**c, "count": 1, "_label_cnt": {c["label"]: 1}}
                order.append(key)
                fresh += 1
        print(f"  滚动 {i+1}/{scrolls}: {len(controls)} 元素, 本轮新控件类型 {fresh}")
        if i < scrolls - 1:
            _api("POST", f"/api/biz/v2/devices/{DEVICE}/command/",
                 {"action": "scroll_down", "params": {}})
            time.sleep(3.5)
    # 模板 label 落地：取出现最多的 label；首次 y 不变
    for k in order:
        m = master[k]
        m["label"] = max(m["_label_cnt"], key=m["_label_cnt"].get)
        m.pop("_label_cnt", None)
    # 组装输出（按首次 y 排序，同屏从上到下）
    merged = [master[k] for k in order]
    merged.sort(key=lambda c: (c["y"], c["x"]))
    total_instances = sum(m["count"] for m in merged)
    _save(page, merged)
    print(f"✅ 滚动采集完成 {page}: {len(merged)} 种控件类型 / {total_instances} 实例"
          f"（{scrolls} 次滚动, {len(scans)} 次扫描）→ {os.path.join(OUTDIR, page + '.json')}")
    return merged


def _save(page, controls):
    json_path = os.path.join(OUTDIR, f"{page}.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"page": page, "device": DEVICE,
                   "captured": time.strftime("%Y-%m-%d %H:%M:%S"),
                   "count": len(controls), "controls": controls}, f,
                  ensure_ascii=False, indent=1)
    write_md(page, controls)
    write_index()
    write_all()


def write_md(page, controls):
    has_count = any("count" in c for c in controls)
    lines = [f"# 控件基线地图: {page}", "",
             f"> 采集 {time.strftime('%Y-%m-%d %H:%M:%S')} | 设备 {DEVICE} | {len(controls)} 控件"
             + ("类型（含滚动加载实例数）" if has_count else ""),
             "> 用途: 修控件先查此表，不现场猜。TikTok 更新后重采 diff 对照。", "",
             "| 类名 | accId | x,y | frame | label | 选中 | 实例 |",
             "|------|-------|-----|-------|-------|------|------|"]
    for c in controls:
        label = c["label"].replace("|", "\\|") if c["label"] else ""
        cnt = c.get("count", "")
        lines.append(f"| `{c['class']}` | `{c['accId']}` | {c['x']},{c['y']} | `{c['frame']}` | {label} | {c['selected']} | {cnt} |")
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


def write_all():
    """合并全部页面到单个文件 control-map-all.md（用户要求的「一个文件」）"""
    files = sorted(f for f in os.listdir(OUTDIR) if f.endswith(".json"))
    lines = ["# TikTok 控件基线地图 · 全量汇总", "",
             f"> 生成 {time.strftime('%Y-%m-%d %H:%M:%S')} | 设备 {DEVICE} | {len(files)} 个页面",
             "> 用途: 修控件先查此表，不现场猜。TikTok 更新后重采 diff 对照，锚点漂移一眼看出。", "",
             "## 页面索引", ""]
    for f in files:
        d = json.load(open(os.path.join(OUTDIR, f), encoding="utf-8"))
        lines.append(f"- `{d['page']}` — {d['count']} 控件（{d['captured']}）")
    for f in files:
        d = json.load(open(os.path.join(OUTDIR, f), encoding="utf-8"))
        lines += ["", f"## {d['page']}（{d['count']} 控件）", "",
                  "| 类名 | accId | x,y | frame | label | 选中 |",
                  "|------|-------|-----|-------|-------|-----|"]
        for c in d["controls"]:
            label = c["label"].replace("|", "\\|") if c["label"] else ""
            lines.append(f"| `{c['class']}` | `{c['accId']}` | {c['x']},{c['y']} | `{c['frame']}` | {label} | {c['selected']} |")
    all_path = os.path.join(OUTDIR, "control-map-all.md")
    with open(all_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"📦 全量汇总已生成 → {all_path}（{len(files)} 页）")


if __name__ == "__main__":
    _login(); _ssh_connect()
    args = sys.argv[1:]
    scrolls = None
    if "--scroll" in args:
        i = args.index("--scroll")
        scrolls = int(args[i + 1]); args = args[:i] + args[i + 2:]
    page = args[0] if args else "current"
    wait = float(args[1]) if len(args) > 1 else 4.0
    timeout = int(args[2]) if len(args) > 2 else 60
    if scrolls:
        collect_scroll(page, scrolls, timeout)
    else:
        collect(page, wait, timeout)
    _ssh.close()
