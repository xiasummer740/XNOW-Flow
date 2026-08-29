# TODO 快照 — 2026-08-29 10:20

## 当前进度
- **v1.4.132 触摸盲区 HID ctx 修复 + 导航 bug 修复**（编译中）：
  - XNTouchSimulator.m `_hidContextID`：client/ctx 缓存 + setMatching 后轮询等服务（≤1.5s）+ ctx_probe 诊断
  - CommandEngine.m `_tapTab` not_home 分支：先触摸 tap home tab → 1.2s 异步复验 → 深链兜底
  - 后端 ws.py 已打点 unknown type 打 data（调试用，已备份 .bak-hid）

## 铁证（已落地）
- **HID 断点 = `_hidContextID` 返回 0**（tap home tab 上报 `hid_diag {msg:"tap_ctx_zero",x:41,y:712}`）
- 符号 dlsym resolve OK（open_search 时 symbols_ok）；touch_diag: `TTKTabBarButton gestures=[UITapGestureRecognizer] target_actions=[]`
- **go_home 假成功**：4 轮深链全失败（snssdk1233:// 空/feed/main/home）→ 18s 耗尽 return NO 却被默认 success，设备困 profile 页
- **设备 id 漂移根因**：i4Tools 重装清 NSUserDefaults/IDFV，IOPlatformUUID 沙盒取不到 → IDFV 兜底漂移（131→7098FAE4）
- **后端 rebind 已完成**：卡 id=2 → iphone_7098FAE4（device_bindings id=12），设备已激活

## 下一步
1. 132 编译打包上传 → 祥哥装机
2. 验 hid_diag ctx_probe：ctx 是否非 0（services 数量决定时序 vs 沙盒无权限）
3. 若 ctx>0 → tap home tab 真切换 → 全回归；若 ctx 仍 0 → HID 路线放弃，转 KVC 完整状态机注入
4. 设备 id 漂移根治：MobileGestalt MGCopyAnswer UniqueDeviceID 替代 IOPlatformUUID（下版）

## 风险备忘
- IOHIDEventSystemClient 在 app 沙盒若 CopyServices 永远空（无 HID 服务权限）→ 轮询也拿不到 ctx → 需换方案
- 后端 ws.py 打了临时调试点，稳定后可还原（.bak-hid 备份）
