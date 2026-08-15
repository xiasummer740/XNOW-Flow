# 2026-08-14 手机当前页实时识别（6页）+ 首页菜单bug根因

## 目标
祥哥要的浮窗菜单**按 TikTok 页面不同**显示 → 必须先**准确识别手机当前页**，且要压掉"多页面共享控件"造成的误判。

## 完成（全部真机实测通过）

### 1. 实时识别闭环（端到端可跑）
```
浏览器 http://127.0.0.1:8091/  点"扫描"按钮
  → live_scan_bridge.py (本机8091, FastAPI)
  → 云端 POST /command action=ui_scan
  → 手机轮询(~1s)执行 → HTTP 上报
  → 云端缓存到内存 _last_ui_scan[device_id]
  → 桥接轮询 GET /devices/{id}/ui-scan/ 直到 ts 变化
  → 本地 recognize() → 返回 页面/分数/证据/固定控件
```
- **连接拓扑关键认知**：手机走 **HTTP 轮询**（`GET /ws/{device}/poll?secret=...` → 204）**不是 WebSocket**！所以 `get_online_devices()` 只列 WS 连接 → 显示 0 是**正常**的，别当故障。指令照常排队下发。
- 云端部署：`/opt/xnow-flow`（flat 结构，uvicorn main:app --port 8000，systemd 服务 `xnow-backend`）。改的是 `routers/ws.py`（ui_scan 分支加缓存）+ `routers/device_commands.py`（加 GET ui-scan 接口）。备份 .bak-20260814 在服务器上。
- **ui_scan 返回键**：`{count, elements:[{class,x,y,frame,acc_id}]}` —— **没有 label/acc_label/isSelected**！判固定/变量只用 class+acc_id+x/y。
- 凭证读取：`ssh_upload.py`/`ssh_run.py` 用 paramiko + `.env.local` 的 XNW_VPS_PASSWORD（**禁止输出凭证**）。本地上传用 base64 走 exec（SFTP 不稳）；Git Bash 要 `export MSYS2_ARG_CONV_EXCL='*'`。
- 桥接重启：`Stop-Process` 旧 python + `Start-Process` 全路径（相对路径会失败）。**改了 page_recognizer.py 必须重启桥接**（启动时 import）。

### 2. 六页识别签名（backend/page_recognizer.py）
| 页 | 分/阈值 | 锚点 |
|---|---|---|
| feed 首页 | 11/3 | acc_id: top_tabs_recomend/feedLikeButton/exploretab… |
| profile 我的 | 15/3 | acc_id: TTKProfileTabVideoButton_0/relation_info_* |
| inbox 收件箱 | 7/3 | 类名: TTKInboxActivityStatusView 等（无acc_id） |
| friends 朋友页 | 6/3 | 类名: TTKFriendsFeedTableViewCell 等 |
| search 搜索 | 7/3 | 类名: AWESearchBar + TTKSearch* |
| recorder 录制/创作页 | 16/3 | acc_id: recorderPageToolBar* / recordPage*（10锚点） |

- **算法**：acc_id 或类名加权投票 → 最高分页 → ≥阈值3才判中，否则"未知"；屏外预加载（y>736）过滤。
- **跨页共享控件实战处理**：搜索框 AWESearchBar 在朋友页也有 → 靠 friends 专属类名(6分)压过 search(3分) 最高分裁决；底部 tab 每页都有但没人给它们签名，无影响。**这是祥哥担心的"多个页面有相同控件"案例，已验证解决**。
- 离线交叉验证：`verify_all_pages.py` 跑 6 份存档 `live_scan*.json`（每页换真机扫出来的），6/6 ✓ 零误判。
- 辅助文件：`fetch_scan.py`（拉云端原始 ui_scan 存档）、`live_scan_bridge.py`、`live_scan.html`、`verify_all_pages.py`、`ssh_upload.py`、`ssh_run.py`。

## 首页菜单 bug 根因（不是配置问题！）
祥哥报"首页浮窗菜单不对"。查证：**手机上是 8/12 旧包，缺 8/14 的页面判定修复**（git 提交 c0c8164/0e280b6/c7458a4：隐藏视图过滤、LIVE 徽章防误判、私信标题限位）。识别逻辑在 iOS 端 `CommandEngine.m _detectPageOnMain`（优先级 live>comment>inbox>profile>home）+ `XNFloatingPanel.m _buildPageMenu`（live/inbox/profile/comment 专属，其余→`_mainMenu` 13项）。

## 本次接力完成（2026-08-15，祥哥拍板后全做）
- iOS `_detectPageOnMain` 补 recorder/friends/search 三页识别 → **8页**（live>comment>recorder>friends>search>inbox>profile>home）
  - recorder: `recorderPage*`/`recordPage*` acc_id 前缀（新增 `_hasAccessibilityIdentifierPrefix:inView:depth:`）
  - friends: TTKFriendsFeedTableViewCell 专属 cell（必须先于 search 判，朋友页也有 AWESearchBar）
  - search: AWESearchBar + TTKSearch* 双命中，防首页/朋友页误判
- 浮窗菜单 `_buildPageMenu`: search/friends→基础3项；recorder→自动发视频(post_video)+基础3项
- 截图上报闭环（祥哥确认"对，就这么干"）：`_performScreenshot` 缩放720px→JPEG 0.6→base64→`[XNURLProtocol sendMessage]`→云端 `_last_screenshot` 缓存→`GET /devices/{id}/screenshot/`→桥接 `/api/screenshot`→live_scan.html「截图查看真机画面」按钮
- CI `build-dylib.yml` 构建成功（xnower-dylib artifact）
- 云端 ws.py/device_commands.py 已部署 + `systemctl restart xnow-backend` + 新接口验证通过
- 本地桥接已重启（Stop-Process + Start-Process 全路径）
- 已打包 `TikTok_XNOW_v1.4.84_BH.ipa`（build-bh-ipa.py，DEFLATED 压缩）
  - ⚠️ 版本号教训：先打了 v1.4.77，但 VPS static 已有 v1.4.79-83（**文档只记到 v1.4.76，VPS 实际已到 1.4.83**，多会话版本漂移）→ 重打 v1.4.84。判断版本源看 **VPS `/opt/xnow-flow/static/` 最高版本 + 1**，别信文档。另：VPS 上 1.4.79-83 全是 8/14 页面修复**之前**构建的，都缺页面判定修复。

## 本次接力再追加（2026-08-15，fan_list 识别 + 自动关注）
### 7. 粉丝/关注列表页识别（第9页）
- 祥哥在粉丝列表页点扫描 → 识别为"未知页面"。真机扫描 `fan_list_scan.json`（287元素）确认 5 类锚点**只在本页出现**（7 份存档零碰撞）：
  | 锚点 | 权重 | 说明 |
  |---|---|---|
  | TTKStoryAvatarView | 3 | 每行故事头像（列表唯一） |
  | TTKRelationButton | 2 | 每行关注/加好友按钮 |
  | AWEUIListCellActionButton | 2 | 每行操作按钮 |
  | GBLFeedStaticLiveMarkView | 2 | 每行 LIVE 标（无"LIVE/直播"文字，不触发 live 页） |
  | AWESlidingTabButton | 2 | 顶部 粉丝/关注 滑动 tab |
  - 得分 11/3。**TTKRelationButton 给 2 不给 3**：其它用户主页也有单个关注按钮，命中(2)<3 不会误判；列表页 5 类全中=11。
- **iOS `_detectPageOnMain`** 优先级更新为 `live>comment>recorder>friends>search>fanlist>inbox>profile>home`，fanlist 检测 = `TTKStoryAvatarView + TTKRelationButton` **双命中**（防其它用户主页误判——那页只有一个 TTKRelationButton）。
- **必须排在 profile 之前**：profile 签名含"作品/粉丝/获赞/关注"后缀 label，粉丝列表顶部"粉丝/关注"滑动 tab 会触发。
- 本地识别器验证：`fan_list` 11/3 ✓，6 份存档零回归。**改 page_recognizer.py 后 bridge 已重启生效**（复测 fan_list_scan.json=fan_list 11/3）。

### 8. 自动关注指令 auto_follow_list（v1.4.85）
- 祥哥需求：粉丝列表点"自动关注" → 循环点右侧 Follow → 上滑 → 再点 → **单次上限200** → 自动停；**日志显示行左侧用户名**。
- 日志格式对齐祥哥示例：`正在关注:<label>` / `关注用户[<用户名>][成功|失败]` / `关注异常[<原因>]`（全仓+git历史搜"正在关注/关注用户/关注异常"均无 → 是外部工具格式，全新实现）。
- 新增 `CommandActionAutoFollowList` + 指令名 `auto_follow_list`，`XNFloatingPanel` fanlist 菜单"自动关注"。
- **滚动用 `_scrollTopListUp` 程序化 setContentOffset**（`_safeScrollBy:` 只对 feed 生效，非 feed 页 no-op；真实滑动手势注入被 `#if 0` 禁用防 TikTok 崩溃）。
- **用户名提取必须 `dispatch_sync(main)`**（走 UIKit 遍历 label）——最早在 execQueue 直接调会线程错。
- 循环停止条件：`followed>=limit(200) / emptyRounds>=3（空滚3次到底）/ failStreak>=5（连续失败5次）`。每 10 个成功打 `📊 已关注 %d/%d`。
- 验证逻辑：点击后 `_buttonStateText:` 取按钮文案，含 已关注/互相关注/关注中/Following/Unfollow/已连接 等 → 成功；无文案 best-effort 判成功。

## 待办（下个接力点）
1. **装机验证 v1.4.85**（替代 v1.4.84，合并 8页+截图+fanlist+自动关注）：① 9 页浮窗菜单（尤其 search/friends/recorder/fanlist 四新页 + 首页完整13项） ② 截图上报（浏览器 http://127.0.0.1:8091/ 点「📸 截图查看真机画面」应显示真机画面） ③ 粉丝列表点"自动关注"：日志显示左侧用户名、循环点 Follow→上滑→再点、200 自动停
2. 验证通过 → 更新 ISSUES.md（「页面感知浮窗菜单真机验证」+「粉丝列表自动关注」两条 待修→已验证），其余待修项顺带真机验证
3. 发版门禁：ISSUES.md 全表「已验证」才发版；此批=页面修复+截图+菜单+fanlist+自动关注（安全第二批 TLS/secret header 等4项待修未含）
4. ⚠️ 上次 v1.4.84 上传被 hold（被 v1.4.85 取代），构建产物清理：删本地 `TikTok_XNOW_v1.4.84_BH.ipa`

## 连接信息
- 云端 192.129.210.52:8000（域名 yunkong.taikon.top 走 Cloudflare 同源）
- 手机 iphone_0ECF42DC（IP 64.186.242.99）
- 本机桥接 http://127.0.0.1:8091/
