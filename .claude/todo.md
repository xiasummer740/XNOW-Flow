# TODO 快照 — 2026-08-29 11:15

## 当前进度
- **v1.4.133 已编译打包上传**（`TikTok_XNOW_v1.4.133_BH.ipa` 374.2 MB → VPS static）：
  - 132 全部修复：XNTouchSimulator `_hidContextID` setMatching 异步→轮询等服务(≤1.5s)+ctx缓存+ctx_probe 诊断
  - 132 导航 bug：CommandEngine `_tapTab` not_home 分支先触摸 tap home tab→1.2s 异步复验→深链兜底
  - **133 新增 Keychain 根治**：XNOWER.m `XN_KeychainReadDeviceId/WriteDeviceId`（service=com.xnow.deviceid），device_id 双写 Keychain，重装 NSUserDefaults 空时先从 Keychain 恢复 → 卡密绑定不失配
- 132 装不了定位 = 设备侧（132 VPS md5=本地=18bce14c，结构同 131，非 IPA 损坏）

## 铁证（已落地）
- **HID 断点 = `_hidContextID` 返回 0**（tap home tab 上报 `hid_diag {msg:"tap_ctx_zero",x:41,y:712}`）
- 符号 dlsym resolve OK（open_search 时 symbols_ok）；touch_diag: `TTKTabBarButton gestures=[UITapGestureRecognizer] target_actions=[]`
- **go_home 假成功**：4 轮深链全失败（snssdk1233:// 空/feed/main/home）→ 18s 耗尽 return NO 却被默认 success，设备困 profile 页
- **设备 id 漂移根因**：i4Tools 重装清 NSUserDefaults/IDFV，IOPlatformUUID 沙盒取不到 → IDFV 兜底漂移（131→7098FAE4）
- **后端 rebind 已完成**：卡 id=2 → iphone_7098FAE4（device_bindings id=12），设备已激活

## 下一步（等祥哥装机 133）
1. 装机 133（132 装到一半报错，需确认设备空间/关 TikTok/换 USB 再试）
2. 验 hid_diag ctx_probe：ctx 是否非 0（services 数量决定时序 vs 沙盒无权限）
3. 若 ctx>0 → tap home tab 真切换 → 全回归（like/follow/search/open_profile/tab/go_home/backup）
4. 验 Keychain：本次装机双写后，下次重装 device_id 不漂移（根治卡密重输）
5. 控件地图 3 页补采（following/comment/edit_profile，tap 导航解锁后）

## 风险备忘
- IOHIDEventSystemClient 在 app 沙盒若 CopyServices 永远空（无 HID 服务权限）→ 轮询也拿不到 ctx → 需换方案（KVC 完整手势状态机）
- 后端 ws.py 打了临时调试点（unknown type 打 data），稳定后可还原（ws.py.bak-hid 备份）
- 132 设备侧装不上原因未定位：装机 133 前先清空间/结束 TikTok 进程
