# -*- coding: utf-8 -*-
"""离线交叉验证：6 份存档扫描 → 识别 → 全对才算过。"""
import json, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "backend"))
from page_recognizer import recognize

CASES = [
    ("live_scan.json",  "feed",     "首页"),
    ("live_scan2.json", "profile",  "我的"),
    ("live_scan3.json", "inbox",    "收件箱"),
    ("live_scan4.json", "friends",  "朋友"),
    ("live_scan5.json", "search",   "搜索"),
    ("live_scan6.json", "recorder", "录制"),
]

all_ok = True
for f, expect, label in CASES:
    path = os.path.join(os.path.dirname(__file__), f)
    if not os.path.exists(path):
        print(f"{label:6s} {f:14s} -> 文件不存在"); all_ok = False; continue
    data = json.load(open(path, encoding="utf-8"))
    r = recognize(data.get("elements", []))
    ok = r["page"] == expect
    all_ok = all_ok and ok
    print(f"{label:6s} {f:14s} -> {r['title']:22s} 分={r['score']}/{r['threshold']} {'✓' if ok else '✗ 实际:' + r['page']}")

print("=" * 50)
print("全部正确 ✓" if all_ok else "有误判 ✗")
