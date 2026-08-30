# TikTok 控件基线地图索引

> 根治「锚点靠猜」：每个关键页面的控件(类名/accId/坐标/label)固化在此，
> 修控件先查表；TikTok 更新后重采对照 diff，锚点漂移一眼看出。

- [comment](comment.md) — 189 控件（2026-08-29 21:46:37）
- [edit_profile](edit_profile.md) — 20 控件（2026-08-30 17:58:42）
- [feed](feed.md) — 63 控件（2026-08-28 19:58:00）
- [following](following.md) — 194 控件（2026-08-29 14:42:37 (log 恢复)）
- [friends](friends.md) — 36 控件（2026-08-30 18:05:47）
- [inbox](inbox.md) — 28 控件（2026-08-30 18:13:34）
- [profile](profile.md) — 73 控件（2026-08-28 22:40:49）
- [search](search.md) — 24 控件（2026-08-30 18:15:01）

## 采集方法
```bash
# 1. 导航设备到目标页面
# 2. 采集
python collect-control-map.py <页面标签>
```
