# TODO 快照 — 2026-08-30 凌晨

## 当前进度（祥哥四指令已执行 3/4）
1. **✅ 闪退选 B**：已文档化不动（TikTok 自身 bug + 崩溃自愈兜底）
2. **✅ 滚动加载采集**：collect_scroll 机制验证（edit_profile 单元格位移）；**4 页滚动采集完成** edit_profile(165)/friends(290)/inbox(250)/search(175)；friends 页重采修复了之前误采成 edit_profile 的脏数据
3. **✅ 自由切页 5/5 打通**：feed=open_tab home / search=open_search / profile=open_tab profile / friends=open_tab friends / inbox=open_tab inbox，每页 ui_scan 判据落位；**go_back 左缘右滑退推入页验证成功**（edit_profile→profile）
4. **⏳ 交互选 C 纯网络层**：未动工，下一大项

## 关键发现（本会话实锤）
- **go_back 是退推入页的唯一现成路径**：`_performGoBack`(CommandEngine.m:2833) 找 Back 按钮 tap（死）→ 兜底左缘右滑 `_simulateSwipeFrom:(5,midY)→(0.6w,midY)`（有效）——之前「open_tab friends 成功但画面还是 edit_profile」的根因就是推入页不随 tab 切换消失
- **open_search 的搜索图标 tap 有效**：图标是手势识别非 UIControl（Lynx 搜索页打开成功）——证明「手势识别的 view tap 有效，UIControl touchUpInside 无效」边界更清晰
- **scroll_down 在列表页不是 no-op**：`_tryPageFeed` 找到 AWENewFeedTableView 走 setContentOffset 路径（日志 offset 736→2944 递增），只是 friends/inbox 列表短/空态滚动无新内容
- **控件地图现 8 页**：feed(63)/search(175)/profile(73)/friends(290)/following(194)/comment(189)/edit_profile(165)/inbox(250)

## 下一步
1. **纯网络层 like/follow/comment/edit（#18）**：运行时内省 MusicallyCore 找请求模型（RepostDiggRequestModel 已确认存在）→ 用 app 网络栈发请求 → 新命令。推入页（following/comment/edit_profile）数据操作也走此层，不依赖 UI 导航
2. 深链补强：验证 snssdk1233://aweme/detail/<id> 打开视频详情 → 评论面板是否可达
3. 验 Keychain：下次重装 device_id 不漂移（133 已双写）

## 风险备忘
- 全局 openai 包损坏，vision 用 `uv run` 绕过
- 设备空闲会崩（TikTok 自身 bug + 低内存），导航/采集多留恢复手段
- 134 无障碍验证版不进正式功能
- 触摸 tap 对 UIControl 全死（四路已证），纯网络层是唯一正解
