# TikTok 控件基线地图索引

> 根治「锚点靠猜」：每个关键页面的控件(类名/accId/坐标/label)固化在此，
> 修控件先查表；TikTok 更新后重采对照 diff，锚点漂移一眼看出。

- [current](current.md) — 64 控件（2026-08-28 21:06:34）
- [feed](feed.md) — 63 控件（2026-08-28 19:58:00）

## 采集方法
```bash
# 1. 导航设备到目标页面
# 2. 采集
python collect-control-map.py <页面标签>
```
