# 问题清单

> 发版门禁依据：发版前全表必须是「已验证」。机制见 `xiangge-env/specs/release-gate.md`。
> 状态机：待修 → 已修待验 → 已验证（= 真机/测试实测通过）

## 🔴 安全（2026-08-11 全面审查发现，第一批已修4项）

| 状态 | 问题 | 来源 | 上次更新 |
|------|------|------|---------|
| 已验证 | SECRET_KEY 无默认值，未配置启动即抛错（防生产沿用 dev 密钥） | 2026-08-11 全面审查 | 2026-08-11 |
| 已验证 | 上传限制 10MB + 拒绝 SVG（防存储型 XSS / 磁盘 DoS） | 2026-08-11 全面审查 | 2026-08-11 |
| 已验证 | 任务/定时任务非 admin 校验设备归属（防跨租户下发） | 2026-08-11 全面审查 | 2026-08-11 |
| 已验证 | 设备鉴权收紧：UUID 校验 + 恒定时间比较 + 关迁移期放行 | 2026-08-11 全面审查 | 2026-08-11 |
| 待修 | 无 TLS 明文传输（uvicorn:8000 公网明文）→ 需 nginx 443 + 设备改 https（第二批） | 2026-08-11 全面审查 | 2026-08-11 |
| 已修待验 | 设备 secret 走 URL 明文进日志 → 已改 header 传输（v1.4.108：XNOWER `_sendCommandToBackend:` 改走 X-Device-Secret header；XNURLProtocol 早已走 header） | 2026-08-11 全面审查 | 2026-08-18 |
| 待修 | batch_login 把解密后账号凭证明文下发 → 明文传输风险归并「无 TLS」项（已做限权 ensure_owned，凭证仅发往用户自有设备；TLS 443 上线后消除） | 2026-08-11 全面审查 | 2026-08-16 |
| 已验证 | get_online_devices 无租户过滤 → 已加 tenant_scope 过滤（device_commands.py:135-140），已部署 VPS 验证存在 | 2026-08-11 全面审查 | 2026-08-16 |

## 🟠 功能（设备端待装机验证）

> 2026-08-15 全自动真机验证（v1.4.88）新增确认问题见下方 🔴/🟠 行，证据见 `VERIFY-REPORT-2026-08-15.md`

| 状态 | 问题 | 来源 | 上次更新 |
|------|------|------|---------|
| 已验证 | **search_keyword 卡死拖垮设备（根因=主线程嵌套 dispatch_sync 自锁）**：v1.4.90 isMainThread 保护生效，**真机实测通过**（2026-08-15 14:30 search_keyword 下发→2s 内完成返回 success→22s 后设备仍响应+check_health 可再下发，死锁彻底解除） | 2026-08-15 真机 | 2026-08-15 |
| 已验证 | **TikTok 每次启动弹"App last updated/Update"升级提示**（2026-08-17 祥哥反馈）：根因=v1.4.102 构建脚本把主 Info.plist 的 CFBundleShortVersionString 从 TikTok 原始 43.7.0 误改为我们的 1.4.104 → TikTok 判定旧版本强制弹更新。**v1.4.105 修复**：ShortVersion 保持 43.7.0 不动，仅递增 CFBundleVersion(437105)。**装机验证通过**：ui_scan TUXDialog=0 无弹窗、页面识别 feed 正常 | 2026-08-17 真机 | 2026-08-17 |
| 部分验证 | **远程导航**：评论区困死已修（v1.4.97b close_overlay 物理移除面板，装机验证 ✅）；**feed 点头像 open_profile 失效**（hitTest 被父容器 TTKFeedInteractionBackgroundView 拦截，AWEStoryAvatarButton 不在响应链）→ v1.4.99/100 XNTouchSimulator tapView: 直接对头像触发（绕过 hitTest），v1.4.101 待装机验证 | 2026-08-15 真机 | 2026-08-16 |
| 已修待验 | **评论区 overlay 关闭后"黑屏"**（祥哥 2026-08-16 反馈）：根因=评论面板关闭后视频播放器未恢复播放（物理移除跳过 TikTok 正常关闭逻辑）→ 无音频无触摸 → iOS 自动锁屏 = 黑屏假象（祥哥手动上滑切视频即恢复，实锤锁屏）。**v1.4.101 修复（代码 v1.4.100）**：① XNOWER.start 禁 idleTimer（自动化设备永不锁屏）② detectCurrentPage 评论检测遍历所有 window（评论面板独立 window 识别不到→close_overlay 从不触发）③ _closeCommentPanel 后 _resumeFeedPlayback 恢复 AVPlayer 播放 ④ 物理移除隐藏空壳评论 window 防触摸拦截 ⑤ ui_scan 全窗口扫描（评论面板控件进 scan，verify 能识别 comment 页）。待装机验证 | 2026-08-16 真机 | 2026-08-16 |
| 待修 | **评论区 overlay 无法关闭 → 设备困死**（v1.4.90 新发现）：_performComment 打开评论面板后无关闭机制；面板弹键盘遮 tab bar，go_home/go_back/snssdk1233://feed 深链均无效。复验脚本 t_navigation "4连pass"是假阳性（设备当时本就在 feed）。修复方向：① _performComment 完成后主动关面板（点 Close 按钮/下滑）② _gotoHomeFeed 开头先关 overlay 再点 tab。（v1.4.97b 物理移除已生效装机验证✅，残留"黑屏"问题并入上行 v1.4.100） | 2026-08-15 真机 | 2026-08-16 |
| 已验证 | **评论按钮按到屏幕外**：v1.4.89 屏内过滤生效，**真机实测通过**（2026-08-15 14:29 comment 命令点击 AWEFeedVideoButton 命中评论区，面板打开，Add comment/Post comment/Read 13 comment replies 等控件全部屏内可见）。注：复验脚本曾误报失败（字段读 label 实为 acc_label，已修脚本） | 2026-08-15 真机 | 2026-08-15 |
| 已验证 | **任务状态全部误报**：后端已上线(2026-08-15 12:26)，实测部署后下发 ui_scan→任务92 done/100分(旧代码89/90/91全failed对照)；task_engine 远程指令不再判失败+WS结果回填。**v1.4.90 复验**：check_health 下发返回 `{'status':'active','health_score':100}`，设备状态正常回传（复验脚本只验设备响应，done/failed 回填见 92 号对照） | 2026-08-15 真机 | 2026-08-15 |
| 已验证 | home 误判 live：首页 feed 直播预览容器不再误判直播间（真实 feed 返回 home 菜单正确）| 2026-08-15 真机 | 2026-08-15 |
| 已验证 | 点赞 like 真机成功：state_diag acc_label='Video liked' | 2026-08-15 真机 | 2026-08-15 |
| 已验证 | open_search 真机成功 + scroll_down 真机成功 | 2026-08-15 真机 | 2026-08-15 |
| 待修 | 页面感知浮窗菜单真机验证：13种页面(feed/评论/直播/主页/编辑资料/私信列表/私信对话/朋友/搜索/录制/粉丝列表/设置)菜单是否正确切换 + 截图上报（其余页面菜单待导航修复后复验） | 2026-08-11 开发 | 2026-08-15 |
| 待修 | 粉丝列表自动关注真机验证：fanlist 菜单"自动关注"循环点右侧Follow→上滑→再点，日志显示左侧用户名，上限200自动停 | 2026-08-15 开发 | 2026-08-15 |
| 部分验证 | collect_fans 采集粉丝崩溃：v1.4.88 修复后**全程无崩溃**（✅ 死锁修复生效），但实际采集不可达（导航坏 P0-2，进不了别人主页）→ collected_data=0。待导航修复后复验采集 | 2026-08-15 真机 | 2026-08-15 |
| 部分验证 | 我的/别人主页区分+菜单重配：**代码/配置已验证正确**（离线复刻：feed=home 无采集三件套；mine=账号管理；other=自动关注/采集/视频），真机不可达（导航坏） | 2026-08-15 真机 | 2026-08-15 |
| 部分验证 | 三个按钮绑定修复：代码已确认 auto_follow→follow、auto_comment_like→like_comment、collect_live→collect_live_users，真机不可达（导航坏） | 2026-08-15 真机 | 2026-08-15 |
| 已验证 | 设备激活失配：卡7YDYWY绑旧UUID与当前device_id不符→403未激活。已SQL更新license绑定，本次会话 license poll 返回 200 = 激活恢复 | 2026-08-15 排查 | 2026-08-15 |
| 已修待验 | **F14 实时翻译断链已修**（v1.4.108）：后端 `toggle_translate` 处理器（device_commands.py 记录设备翻译偏好 `_device_translate_prefs` + `GET /devices/{id}/translate-pref/` 查询）+ `/api/biz/v2/translate/` 双鉴权（user JWT / 设备 secret header）+ 设备端扫描循环（XNOWER `_scanAndTranslateDMs` 私信页检测文案→XNURLProtocol `translateText:` 调后端→日志展示；F15 翻译语言存储已被扫描循环消费）。待装机验证 | 2026-08-11 开发 | 2026-08-18 |
| 已修待验 | **F16 口令入口已移除**（v1.4.108，祥哥拍板「去掉」）：XNFloatingPanel 私信页菜单删除「设置口令」+ 删除孤儿 handler（XNFloatingPanel.m），口令走后台 reply_templates 配置。待装机验证 | 2026-08-11 开发 | 2026-08-18 |
| 待修 | 回关自动私信真机验证：关注成功后自动私信(取话术) | 2026-08-12 开发 | 2026-08-12 |
| 待修 | 统一素材库/视频管理/广告管理页真机验证（后端已上线） | 2026-08-12 开发 | 2026-08-12 |
| 待修 | 设备端 poll 静默失败无重连 → 掉线后永不恢复（昨晚 go_home 后掉线根因，需装机新版） | 2026-08-10 真机 | 2026-08-11 |
| 待修 | 共享 forward session 被 finishTasksAndInvalidate 销毁（copy-paste 错误，潜在崩/卡雷）→ **已修**：XNURLProtocol.m:429 改独立 session 不复用共享，待装机验证 | 2026-08-11 全面审查 | 2026-08-16 |
| 待修 | 授权检查把网络瞬时失败当未激活 → 清激活停轮询（潜在雷） | 2026-08-11 全面审查 | 2026-08-11 |
| 待修 | v1.4.76 follow 验证：state_diag 应显示 "Following X"（上次设备掉线未完成） | 2026-08-10 真机 | 2026-08-11 |
| 待修 | 硬件 UDID(IOPlatformUUID) 能否拿到 + 激活是否稳定 | 2026-08-10 接力 | 2026-08-11 |
| 待修 | 其他设备命令真机验证：发视频选片/like_comment/open_live/follow_user/comment_video | 2026-08-10 接力 | 2026-08-11 |
| 待修 | 硬件UDID若拿不到 → 备选：爱思UDID手动绑定 / 放宽卡绑定 | 2026-08-10 接力 | 2026-08-11 |
| 已修待验 | **F21/F26 停止采集错配已修**（v1.4.108）：CommandEngine 新增 `CommandActionStopCollect`（stop_collect 系列→置 `isCollectingData=NO`）；5 个采集 case（fans/videos/comments/live_users/likes）前置 YES/后置 NO；4 处 while 循环加 `!isCollectingData` 停止检查；浮窗停止按钮改发 `stop_collect`（不再误发 `nurture_stop`）；顺带修复 `_sendCommandToBackend:` 设备 secret 改走 X-Device-Secret header。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **F6/B16 保存视频已修**（v1.4.108，祥哥拍板「双做」）：`_performSaveVideo` ①下载无水印视频存相册 ②XNURLProtocol `uploadVideoToBackend:` 上传后台 ③后端 `/videos/save/` 落 Media 表（设备 secret 鉴权、200MB 上限、multipart 文本字段在前修复）。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **B10 发现页按钮已删**（v1.4.108，祥哥确认发现页=For You 首页与 B9 重复）：control.html 移除「🔍 发现页」按钮；open_tab discover 坐标兜底保留防旧指令。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **F13 直播间重复入口已删**（v1.4.108，祥哥拍板合并删一个）：XNFloatingPanel 直播页菜单删除「开始采集」，留「采集直播间粉丝」（collect_live）。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **F27 快捷入口已加**（v1.4.108，祥哥拍板加「打开搜索/回首页」）：XNFloatingPanel `_buildPageMenu` 的 search/friends 分支加「打开搜索」「回首页」（执行后自动收起面板防遮挡）。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **B41 切换账号已改真切换**（v1.4.108，祥哥拍板 A+B）：A=`_performSwitchAccount:` 按 aweme_id/aweme_number 在 AccountPool 查目标账号→交 `AccountSwitcher switchToAccount:` 真切换（快照恢复→Token/Cookies 注入→UI 登录）；备份时账号存 aweme_id；B=control.html 账号操作卡加「目标账号」下拉（后台 `/accounts/` 接口按设备加载）选账号传 aweme_id。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 待修 | **F12 采集点赞名不副实**（产品对齐坐实）：`_performCollectLikes` 与 F11 采集直播间粉丝**同一套 `_collectLiveRoomUsers` 逻辑**，仅 sourceType 标签不同，没真采"点赞用户" → 待拍板：真做（开点赞列表采）or 删按钮 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **账号管理页「新增账号/备份当前账号」点了没反应**（祥哥 v1.4.108 装机实证，2026-08-18）：根因=overlay 独立窗口无 rootViewController，`_presentAlert:` 找 ws.keyWindow（点到浮窗后可能是 overlay 窗口）且 rootVC 为 nil → present 静默失败 = 点了没反应。**v1.4.110 修复**：XNOWER.m overlay 挂透明 host rootVC + 浮窗挂 hostVC.view + XNPassThroughWindow hitTest 跳过 hostVC.view 保穿透；XNFloatingPanel.m `_presentAlert:` 改从 `self.window.rootViewController` present（alert 必然显示在浮窗之上）。待装机验证。**此条是 B41 账号池验证的前置解锁** | 2026-08-18 真机 | 2026-08-18 |

> 待办策略：攒批 3-5 项一次装机测，不单点发版。
> 未列问题但新发现的 → 加一行状态「待修」。
