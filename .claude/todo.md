# TODO 快照 — 2026-08-29 22:00

## 当前进度
- **✅ 控件基线地图 7 页全齐（2026-08-29）**：feed(63) / search(64) / profile(73) / friends(63) / following(194) / comment(189) / edit_profile(54) = 700 控件
  - 3 缺页全部人工导航采集：following 从 VPS 日志恢复（设备闪退数据没丢）、comment/edit_profile 直接采集
  - 视觉模型确认 edit_profile=编辑资料表单（Name/Username/Bio/Pronoun/Links/Fundraiser）
- **✅ 触摸盲区专项收尾**：四路全死（HID/KVC/sendAction/accessibilityActivate），134 acc_click 验证 5 项全 ok=false
- **🔥 闪退根因实锤**：`NSInternalInconsistencyException: background thread 改布局`（VPS log 14:46:11），`AWEPublishProgressDefaultWrapper` 卡死上传浮层三页残留，疑似元凶

## 铁证（已落地）
- 134 acc_diag 五行全 ok=false → ISSUES.md 验证表
- collect-control-map.py 两个 bug 已修（元素上报等待 + 负数坐标正则）
- 截图→视觉识别流程打通（uv run vision.py 绕过坏 openai 包；后端 key=image_base64）

## 下一步（等祥哥拍板方向）
1. **闪退专项**（新批次首选）：后台线程改布局崩溃 —— 找卡死上传来源，查 post_video 失败清理，尝试 main 线程兜底
2. **触摸全死后 like/follow/comment/edit 怎么办**：
   - XCUITest 测试框架注入（唯一 Apple 官方合成触摸路径，重构大）
   - 深链扩展（部分导航可用，like/follow/comment 无深链）
   - 接受真机退化，转纯网络层能力
3. 验 Keychain：下次重装 device_id 不漂移（133 已双写）
4. 后端 ws.py 临时调试点（acc_diag/unknown type 打日志）稳定后可还原

## 风险备忘
- 全局 openai 包损坏（openai.types.beta.threads 缺模块），vision 需用 `uv run` 绕过
- 设备反复闪退（bg 线程布局崩溃），手工导航采集要多留恢复手段
- 134 是无障碍验证版，不进正式功能
