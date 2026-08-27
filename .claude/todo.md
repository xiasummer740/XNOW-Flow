# TODO（2026-08-26 深夜停工快照 → 明早接续）

## 当前进度
- ✅ v1.4.125 edit_profile 崩溃**根因已实锤**：dispatch_sync 主线程嵌套自锁（`_performEditProfile` 外层 `dispatch_sync(main)` 包 `_tapTab` 内部 `dispatch_sync(main)` → 主线程自锁 → watchdog 杀进程），非坐标问题
- ✅ **已修 3 处**（CommandEngine.m）：`_performEditProfile` / `_performLogout` / `_performRegisterAccount` 去掉外层 dispatch_sync 包装，直接调 `_navigateToProfile`（=open_tab 已验证稳定模式）
- ✅ **已重建上传**：`TikTok_XNOW_v1.4.125_BH.ipa`（374.2MB）@ /opt/xnow-flow/static/，装机链接 http://192.129.210.52/TikTok_XNOW_v1.4.125_BH.ipa
- ✅ 云控讲解.pptx 98页全部识别 → `docs/云控功能清单.md`（手机/网页分区 + XNOW 缺口对照 + 三批路线图）

## 明早祥哥第一件事：装机验证 125
1. i4Tools 装 `TikTok_XNOW_v1.4.125_BH.ipa`
2. 后台下发 `edit_profile {"nickname":"outshine1","signature":"测试签名来自云控"}`
3. 期望：VPS 日志全 STEP（start→at_profile→name_tap→name_set→bio_tap→bio_set→save→done）+ 无 CRASH + 真机昵称变 outshine1
4. 顺带验：logout / register 命令不再闪退

## 验证通过后的下一步（按功能清单三批路线）
- 第一批·假成功治理：search_keyword / follow_user(username深链失败) / like·follow 用 Safe 版 / void 命令默认兜底 L643 / comment·share 假成功
- 第二批·补后台：视频采集入库 → 素材库 → 批量取关 → 指定视频评论 → 自动回复 → 批量养号参数 → 设备实时监控
- 第三批·填手机端：直播粉丝真采、实时翻译、快捷指令养号

## 待办（旧，未完成）
- F12 采集点赞名不副实（与 F11 同一套逻辑）→ 待拍板真做 or 删按钮
