# TODO 快照 — 2026-08-29 深夜

## 当前进度
- **✅ 控件基线地图 7 页全齐（2026-08-29）**：feed(63) / search(64) / profile(73) / friends(63) / following(194) / comment(189) / edit_profile(54) = 700 控件
- **✅ 触摸盲区专项收尾**：四路全死（HID/KVC/sendAction/accessibilityActivate），134 acc_click 验证 5 项全 ok=false
- **✅ 闪退专项深挖完成（2026-08-29 深夜）**：唯一带栈崩溃(14:46 NSInternalInconsistencyException) 调用栈 0 帧是我们 dylib = **TikTok 自身后台线程改布局 bug**；`AWEPublishProgressDefaultWrapper`「上传卡死」假设**证伪**（7 页全常驻休眠 overlay）；今天 4 段崩溃全空闲时段、无一是我们指令；昨天 open_tab watchdog 崩已由 129 修复且今天全过

## 铁证（已落地）
- 14:46 崩溃调用栈逐帧分析：objc_exception_throw→CoreAutoLayout→UIKitCore→**MusicallyCore awemeMain ×3**→QuartzCore→pthread，无 XNOWER/CommandEngine 帧
- post_video/publish 指令历史核对：从未下发过
- 崩溃时间线：扫描后空闲 4 分钟崩、心跳断→重启上报 pending；ok+ok 成对 = jetsam/SIGKILL 特征
- ISSUES.md 闪退段已改写为完整实锤结论

## 下一步（等祥哥拍板方向）
1. **闪退自愈/规避**：TikTok 侧 bug 无法根治 → 三选：①swizzle 吞异常（高风险，需拍板）②依赖崩溃自愈(已具备)③避开内存重页面
2. **触摸全死后 like/follow/comment/edit 怎么办**：
   - XCUITest 测试框架注入（唯一 Apple 官方合成触摸路径，重构大）
   - 深链扩展（部分导航可用，like/follow/comment 无深链）
   - 接受真机退化，转纯网络层能力
3. 验 Keychain：下次重装 device_id 不漂移（133 已双写）
4. 后端 ws.py 临时调试点（acc_diag/unknown type 打日志）稳定后可还原

## 风险备忘
- 全局 openai 包损坏（openai.types.beta.threads 缺模块），vision 需用 `uv run` 绕过
- 设备空闲会崩（TikTok 自身 bug + 低内存），手工导航采集要多留恢复手段
- 134 是无障碍验证版，不进正式功能
