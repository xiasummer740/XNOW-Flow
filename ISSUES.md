# 问题清单

> 发版门禁依据：发版前全表必须是「已验证」。机制见 `xiangge-env/specs/release-gate.md`。
> 状态机：待修 → 已修待验 → 已备待发 → 已验证（= 真机/测试实测通过）
> 攒批门禁：至少 3 项「已修待验」才编译打包（见 CLAUDE.md 发版门禁），紧急单发需祥哥特批

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
| 已修待验 | **硬件 UDID(IOPlatformUUID) 已实现**（v1.4.115，祥哥 2026-08-17 抱怨「又要输卡密」）：根因=每次 i4Tools 装机=全新安装，NSUserDefaults/Keychain/IDFV 全清→device_id 漂移→卡密绑定失配→又要输卡密。**v1.4.115 根治**：XNOWER.m `XN_HardwareUDID()` 用 IOKit 读 IOPlatformUUID（硬件级标识，重装/重签不变）取前8位做 `iphone_<hw>`，IOKit 失败回落 IDFV（零风险）；编译链接已加 `-framework IOKit`。待装机验证（= 115 装后自动激活不再输卡密） | 2026-08-17 真机 | 2026-08-18 |
| 待修 | 其他设备命令真机验证：发视频选片/like_comment/open_live/follow_user/comment_video | 2026-08-10 接力 | 2026-08-11 |
| 待修 | 硬件UDID若拿不到 → 备选：爱思UDID手动绑定 / 放宽卡绑定 | 2026-08-10 接力 | 2026-08-11 |
| 已修待验 | **F21/F26 停止采集错配已修**（v1.4.108）：CommandEngine 新增 `CommandActionStopCollect`（stop_collect 系列→置 `isCollectingData=NO`）；5 个采集 case（fans/videos/comments/live_users/likes）前置 YES/后置 NO；4 处 while 循环加 `!isCollectingData` 停止检查；浮窗停止按钮改发 `stop_collect`（不再误发 `nurture_stop`）；顺带修复 `_sendCommandToBackend:` 设备 secret 改走 X-Device-Secret header。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **F6/B16 保存视频已修**（v1.4.108，祥哥拍板「双做」）：`_performSaveVideo` ①下载无水印视频存相册 ②XNURLProtocol `uploadVideoToBackend:` 上传后台 ③后端 `/videos/save/` 落 Media 表（设备 secret 鉴权、200MB 上限、multipart 文本字段在前修复）。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **B10 发现页按钮已删**（v1.4.108，祥哥确认发现页=For You 首页与 B9 重复）：control.html 移除「🔍 发现页」按钮；open_tab discover 坐标兜底保留防旧指令。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **F13 直播间重复入口已删**（v1.4.108，祥哥拍板合并删一个）：XNFloatingPanel 直播页菜单删除「开始采集」，留「采集直播间粉丝」（collect_live）。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **F27 快捷入口已加**（v1.4.108，祥哥拍板加「打开搜索/回首页」）：XNFloatingPanel `_buildPageMenu` 的 search/friends 分支加「打开搜索」「回首页」（执行后自动收起面板防遮挡）。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 待修 | **智能浏览闪退**（祥哥 2026-08-20 反馈，点「🌐 智能浏览」即闪退）：根因=`_performSmartBrowse`（CommandEngine.m:2523）主线程同步执行 点赞→sleep 0.5→关注→上滑，违反 v1.4.103 养号防崩设计（"上滑后立刻互动会点到重建中的视频 cell → EXC_BAD_ACCESS 崩"）。修复方向：互动动作间加长延时 + 上滑后延迟再互动 / 拆异步 | 2026-08-20 真机 | 2026-08-20 |
| 待修 | **修改资料输入框无法输入**（祥哥 2026-08-20 反馈，昵称/签名框输不进文字）：根因=`_performEditProfile`（CommandEngine.m:3230）`_findTextFieldWithPlaceholderInView` 只找 UITextField 按 placeholder 关键词匹配后直接 `nameField.text=` 赋值；TikTok 输入框可能是 UITextView/受控组件 → 匹配不到或赋值不生效。修复方向：兼容 UITextView + 模拟编辑事件 | 2026-08-20 真机 | 2026-08-20 |
| 待修 | **关注按钮点不上**（祥哥 2026-08-20 实测，后台「➕ 关注」下发后未点上）：根因=`_performFollow`（CommandEngine.m:1056）依赖 `_findVisibleViewWithLabel:@"Follow"` 命中 FollowPromptView 的 Follow 按钮，TikTok 版本结构差异可能找不到 → 固定坐标兜底易点偏。v1.4.76 follow 条目（上行）从装机起从未真机验证通过 | 2026-08-20 真机 | 2026-08-20 |
| 已修待验 | **后台网页输入框只能输一个字符 + 点按钮页面跳回顶部**（祥哥 2026-08-20 反馈）：根因=DeviceControl.tsx 的 Btn/Card/Label/Input/Select 组件定义在组件函数体内 → 每次渲染创建新函数引用 → React 判定组件类型变化 → 卸载重挂全部 input/button → 输入框 state/焦点丢失（输一个字符后错乱）、页面滚动跳动。**已修**：5 个组件移到模块顶层（类型稳定不再重挂）。本地真实浏览器验证：输入 "hello" 完整保留 + 按钮点击 scrollY 不变（delta=0）。待祥哥强刷(Ctrl+F5)验证 | 2026-08-20 真机 | 2026-08-20 |
| 已修待验 | **B41 切换账号已改真切换**（v1.4.108，祥哥拍板 A+B）：A=`_performSwitchAccount:` 按 aweme_id/aweme_number 在 AccountPool 查目标账号→交 `AccountSwitcher switchToAccount:` 真切换（快照恢复→Token/Cookies 注入→UI 登录）；备份时账号存 aweme_id；B=control.html 账号操作卡加「目标账号」下拉（后台 `/accounts/` 接口按设备加载）选账号传 aweme_id。待装机验证 | 2026-08-18 产品对齐 | 2026-08-18 |
| 待修 | **F12 采集点赞名不副实**（产品对齐坐实）：`_performCollectLikes` 与 F11 采集直播间粉丝**同一套 `_collectLiveRoomUsers` 逻辑**，仅 sourceType 标签不同，没真采"点赞用户" → 待拍板：真做（开点赞列表采）or 删按钮 | 2026-08-18 产品对齐 | 2026-08-18 |
| 已修待验 | **账号管理页「新增账号/备份当前账号」点了没反应**（祥哥 v1.4.108 装机实证，2026-08-18）：根因=overlay 独立窗口无 rootViewController，`_presentAlert:` 找 ws.keyWindow（点到浮窗后可能是 overlay 窗口）且 rootVC 为 nil → present 静默失败 = 点了没反应。**v1.4.110 修复**：XNOWER.m overlay 挂透明 host rootVC + 浮窗挂 hostVC.view + XNPassThroughWindow hitTest 跳过 hostVC.view 保穿透；XNFloatingPanel.m `_presentAlert:` 改从 `self.window.rootViewController` present（alert 必然显示在浮窗之上）。待装机验证。**此条是 B41 账号池验证的前置解锁** | 2026-08-18 真机 | 2026-08-18 |
| 已修待验 | **备份当前账号资料全空 + 前置拦截**（祥哥 v1.4.111/112 装机实证，2026-08-18）：①资料全空根因=AccountManager.currentAccount 需 /user/ 捕获（没进个人页→空）+ NSUserDefaults 启发式没命中。②v1.4.112 加了「资料空→导航个人页触发捕获」兜底后，装机又暴露**面板前置检查拦截**：`_promptBackupCurrentAccount` 在 `currentAccount==nil && activeAccount==nil` 时直接 return「未检测到当前账号」（新装本地池空、没进过个人页→必中），备份根本没执行。**修复**：v1.4.112 把 `_detectCurrentAccountFlow` 提为公开 `detectCurrentAccountFlow` + `backupCurrentAccount` 资料无 aweme_id 时先导航个人页触发 /user/ 捕获；**v1.4.113 删除面板 return**，由 backupCurrentAccount 内部做真实登录态检测（session/cookie）+ 资料抓取。待装机验证（=备份后账号有完整昵称/头像/ID + 后端 B41 账号池同步） | 2026-08-18 真机 | 2026-08-18 |
| 已验证 | **备份抓成正在浏览的视频作者**（祥哥 v1.4.115 装机实证，2026-08-19）：导航个人页+UI扫描兜底全窗口找 @ 标签，视频流里的 @作者 被误抓成"当前账号"（祥哥要的是自己的号，且**要求任意页面都能直接备份**，不一定在个人主页）。**v1.4.116 根治**：①`_extractProfileFromDefaults` 深度递归扫所有嵌套 dict/JSON（原只扫顶层+特定key组合→TikTok 结构一嵌套就没命中）②**cookie uid_tt 消歧**：TikTok 登录必设 uid_tt（登录用户数字ID），只认它匹配的账号 dict，视频作者缓存永不误选 ③`detectCurrentAccountFlow` 导航兜底降为最后手段（v1.4.115 已加 profile_mine 确认才扫描）④新增 `dump_login` 诊断命令 + 备份失败自诊断（NSUserDefaults key 名 + cookies 域名，**不含值**，上报 server.log → 若提取仍失败，据真实结构写精准提取，不盲猜）。**真机验证通过**：任意页面点备份抓到 @outshine83（祥哥确认浮窗显示 Outshine/@outshine83） | 2026-08-19 真机 | 2026-08-19 |
| 已修待验 | **备份账号国家不显示**（祥哥 v1.4.116 装机实证，2026-08-19）：备份成功（Outshine/@outshine83 显示）但「国家:—」。根因=country 只认 `region`/`country` 两个键且要求 NSString，TikTok 缓存 dict 字段名可能不同或为 NSNull/非字符串。**v1.4.117 修复**：①`_extractCountryFromDict` 多键位提取（region/country/display_region/country_code/region_code/ip_location/location/area）+类型安全 ②同 uid 多缓存择优（带国家>完整度，仅同账号安全）③备份成功也上报 profile_keys+country 证据（不含值）→server.log 可核实真实字段名 ④面板国家 code→中文名显示。**v1.4.118 再修**：117 装机实测（祥哥 2026-08-24 点备份）profile_keys 含 `act_country` 但 country 值未上报 → keys 数组加 `act_country` + L182 不再用固定 country 键覆盖成空（`_extractCountryFromDict:profile ?: self.lastMatchedCountry`）。**v1.4.119 待装机验证**（=备份后浮窗显示国家，如 🇺🇸 美国） | 2026-08-19 真机 | 2026-08-24 |
| 已验证 | **智能浏览闪退**（祥哥 2026-08-20 反馈，点「🌐 智能浏览」即闪退）：**v1.4.119 实锤根因**（VPS 日志 polled smart_browse → 23s 后 CRASH last_action=smart_browse）=`_performSmartBrowse` 外层 `dispatch_sync(main)` block 内又调 `_performLike`/`_performFollow`（内部各自 `dispatch_sync(main)`）→ 主线程嵌套同步自锁 → 系统杀进程。**修复**：互动改为直接调用（内部已切主线程，不再嵌套），上滑单独 `dispatch_sync(main)`（内部不切），互动间加 1.0-1.5s 长延时等 UI 重建。**v1.4.121 真机验证通过**（2026-08-25 远程下发）：`smart_browse {'status':'success','likes':3,'follows':3,'scrolls':14,'duration':104}`——跑满 104s 无闪退，顺带自动关注 3 个账号 | 2026-08-20 真机 | 2026-08-25 |
| 已修待验 | **修改资料输入框无法输入**（祥哥 2026-08-20 反馈，昵称/签名框输不进文字）：根因=`_performEditProfile` 只找 UITextField 按 placeholder 关键词匹配且直接赋值不点焦点 → TikTok 输入框可能是 UITextView/受控组件 → 匹配不到或赋值不生效。**v1.4.119 修复**：新增 `_setEditableFieldText:` ①先按 placeholder 找 UITextField ②没有则找 UITextView ③先 `_safeTapAtPoint` 点焦点再赋值 ④发对应 EditingChanged/TextDidChange 通知。**v1.4.123 再修（2026-08-25 真机实测暴露）**：119 只修了输入框赋值，但**编辑按钮定位失败**——`_findButtonWithAnyLabel` 按 label `"Edit profile"`（带空格）匹配 accId `user_info_manage_edit_profile`（下划线）containsString 不命中 → 找不到按钮 → 坐标兜底 (width-40, height*0.38)=(374,340) 点偏 → **编辑资料页根本没打开** → 昵称没改（控件树仍显示 Outshine/@outshine83）。新增 kAccEditProfile 常量，`_performEditProfile` 优先 `_findVisibleViewWithAccId` 定位（同 follow 模式），label 兜底，坐标兜底仅最后手段。**v1.4.123 装机部分验证（2026-08-26）**：accId 定位有效（设备在个人主页时编辑按钮精确命中、编辑页可打开）✅；但 TikTok 编辑页改版为列表式（Name 行入口、主页面无输入框/Save），123 流程仍填不上昵称。**v1.4.124 再修（2026-08-26）**：①`_navigateToProfile` 改用 `_tapTab:@"profile"`（旧坐标 (364,686) 命中不了底部 tab→从 feed 切不到个人主页→编辑按钮找不到→假成功）②点 Name 行(y≈270)/Bio 行(y≈438)进子页→子页唯一输入框赋值→点右上角 Save(w-34,42) ③`_setEditableFieldText` placeholder 匹配失败回退第一个可见可交互输入框 ④新增 `tap` 命令（x/y 坐标点击）。**v1.4.124 装机崩溃（2026-08-26 真机 14:20:21，VPS 日志 CRASH last_action=edit_profile）**：后端 batch_edit_profile 会随机抽「昵称+签名」同时下发，双段执行时 Name 行硬编码 y=270 偏上沿易点不中、Bio 行 y=438 实际落在 Username 行 → 签名文本赋给用户名 → TikTok 用户名校验/保存崩溃。**v1.4.125 修复（2026-08-26 深夜装机实测+根因升级）**：坐标改 Name→y=292、Bio→y=523（真机 tap 逐行实测，屏幕 414x896）+ `_setEditableFieldText` 赋值位置校验（输入框 y 须在屏高 50~80%，防误赋错误页面输入框）+ 赋值失败不点 Save（防状态错乱崩）+ edit_profile 全流程 `_logStep` 步骤上报。**但 125 装机后仍崩（2026-08-26 深夜实测）：两次 edit_profile 都只有 `edit_profile:start` 就死、无任何后续 STEP，设备离线（未上报 ui_scan）；隔离测试 `open_tab profile` 单独导航稳定成功（page=profile）。实锤真正根因=dispatch_sync 主线程嵌套自锁**：`_performEditProfile` 外层 `dispatch_sync(main){ _navigateToProfile }`，而 `_navigateToProfile`→`_tapTab` 内部第一行又是 `dispatch_sync(main)` → 主线程嵌套同步自锁 → iOS watchdog 杀进程（同 v1.4.119 智能浏览闪退同款根因）。坐标 270/438 只是次要诱因。**修复（已编码重新构建）**：`_performEditProfile`/`_performLogout`/`_performRegisterAccount` 三处去掉外层 `dispatch_sync(main)` 包装，直接调 `_navigateToProfile`（命令在后台线程执行，`_tapTab` 内部自带切主线程 = open_tab 已验证稳定模式）。待重新装机验证（=后台同时改昵称+签名真机生效不崩） | 2026-08-20 真机 | 2026-08-26 |
| 部分验证 | **关注按钮点不上**（祥哥 2026-08-20 实测，后台「➕ 关注」下发后未点上）：**v1.4.119 实锤**（VPS 日志 state_diag before=after='Follow xo.sleepybrunette' success=False）=命中 label 文本但点击无效（label 非 UIControl，合成触摸点不到按钮本体）。**修复**：①优先 accId=`kAccFollow` 定位按钮 ②label 命中后向上找最近 UIControl 按钮本体 ③按钮是 UIControl 则先 `sendActionsForControlEvents` 再 `_safeTapAtPoint`。**v1.4.121 真机验证**：智能浏览内部自动关注 3 个账号全部成功（`smart_browse follows:3`，走同一 `_performFollow` 逻辑）；**后台独立「➕ 关注」命令待单独实测**（=state_diag success=True 或 label 变 Following） | 2026-08-20 真机 | 2026-08-25 |
| 已修待验 | **设备重装后 Keychain UID 变化 → 卡激活失败**（2026-08-18 第三次出现）：UID 三次重装三次变（451D→68D9→F8C0），每次 SQL 改绑救急。**根因定位**：激活/授权/浮窗机器码全走 `[DeviceIdentity deviceUID]`（Keychain UUID，注入 TikTok 重装/重签即清空）；而命令主键 `device_id`=iphone_0ECF42DC（IDFV 前8位 + NSUserDefaults 持久化，重装稳定）与 WS 鉴权（device_bindings 表 secret）链路稳定（poll 一直 200）。**v1.4.114 根治**：授权检查×2/激活/浮窗显示/复制机器码全部改用 `self.deviceId`（XNOWER.m 4处+XNFloatingPanel.m 2处），卡密已改绑 `iphone_0ECF42DC`，DeviceIdentity 类弃用保留（待 #49 硬件UDID拍板）。待装机验证（= 114 装后自动激活，重装不再失配） | 2026-08-18 真机 | 2026-08-18 |

> 待办策略：攒批 3-5 项一次装机测，不单点发版。
> 未列问题但新发现的 → 加一行状态「待修」。

## v1.4.121 待办

### [已修待验] device_id 漂移 → 卡密激活失配
- **现象**：i4Tools 重装后设备上报 device_id 变化（iphone_8E65C9CA → iphone_A6D8F9B4），卡密绑定旧 ID → 激活 400「卡密已绑定其他设备」
- **根因**：XNOWER.m XN_HardwareUDID() 用 IOPlatformUUID，IOKit 失败回落 IDFV（装机即漂移，代码注释已写明）
- **临时处置**：2026-08-25 已把卡密 7YDYWYSKMKZAH06Q 改绑到 iphone_A6D8F9B4
- **后端根治（已部署 2026-08-25，VPS 重启成功 PID 868282）**：licenses.py activate 加「设备漂移自动重绑」——卡密 active 但绑旧 device_id 且旧设备在线→拒绝；旧设备离线→自动改绑到新 device_id（装机漂移典型场景，用户免改库不再输卡密）
- **待验证**：重装一次 IPA 后 device_id 变化 → 输入卡密激活应自动重绑成功，不再 400

### [已备待发] 备份账号国家不显示（v1.4.122 cookie 兜底）
- **状态**：v1.4.122 代码已并入 v1.4.124（基于最新源码编译，含 `_countryFromCookies`），装 124 一次验；122 单包仍在 static 备查
- **121 证据链**：2026-08-25 远程 backup_account success（`已备份账号 #1`），但 result 无 country 字段（121 只在非空才上报）→ 国家提取在 121 仍空
- **122 必成证据**：diagnostic cookies 已含 `store-country-code@.tiktok.com/.tiktokv.com/.tiktokw.us/.tiktokw.eu/.tiktokv.us` 全部带值 → `_countryFromCookies` 兜底必读到国家码
- **验收**：备份后浮窗显示国家（如 🇺🇸 美国）
- **2026-08-26 实测**：`store_country_code:'gb'`（`_countryFromCookies` 读到 cookie 值，英国）✅ 国家抓取已验；但 backup_account 整体 failed「未检测到登录态」——账号 dict 匹配失败（NSUserDefaults 出现 `1787667260:dict`/`NHAccountManager*:archive` 新结构识别不到）+ 123 `_navigateToProfile` 坏致网络捕获兜底失败 → 国家无机会显示。**v1.4.124 装机实测 14:19:22 backup_account success（`已备份账号 #1 登录态`, country:gb）** —— 124 `_navigateToProfile` 修复生效，备份+国家显示链路已验证 ✅（状态→已验证）
- **验收**：备份后浮窗显示国家（如 🇺🇸 美国）

### [已备待发] 修改资料改昵称（v1.4.123+124+125，详见上方「已修待验」行）
- **状态**：v1.4.123 已实测 accId 有效（编辑页可开）；v1.4.124 列表式适配但**装机崩溃**（详见已修待验行，坐标 270/438 硬编码错 → 签名误赋用户名崩）；**v1.4.125 死锁修复装机验证通过（2026-08-27 实测：edit_profile 全 STEP start→at_profile→name_tap→name_set→bio_tap→bio_set→save→done 跑完，11s 无 CRASH success）**；**但暴露流程新 bug：TikTok 改名弹「Update name?」确认框（7天一次）代码没处理 → 改名不生效 + 签名段在昵称子页误执行把签名覆盖进昵称框（截图实测 昵称框=测试签名来自云控 + 弹窗卡住）→ 已点 Cancel 恢复，昵称 Outshine 未被污染。v1.4.126 修复（构建中）**：新增 `_tapDialogConfirmIfPresent`（识别 TUXDialogHighlightBackgroundButton 弹窗点最右 Confirm）+ 昵称 Save 后点 Confirm + 签名段先清残留弹窗 + `_setEditableFieldText` 加 allowFallback=NO（签名段必须匹配 Bio placeholder 才赋值，禁回退第一个输入框防覆盖昵称）
- **验收**：后台同时改昵称+签名 → 真机编辑资料页打开、昵称框填入、保存生效且**不崩**（昵称变 outshine1）

## v1.4.127 攒批（装 127 一次验全批 + 126 并入）→ 装机验证结果

> **装机验证（2026-08-28）**：装 `TikTok_XNOW_v1.4.127_BH.ipa` 逐项实测。**结果：4 项验证、3 项未完成**——① backup ✅；③search ❌、④follow ❌、⑤open_profile ❌（三者同一根因=**触摸盲区**：TikTok 搜索/关注/头像按钮对 XNTouchSimulator 合成触摸不响应）；⑥like ❌（127 sendActions 不点亮红心）；**⑤ open_tab profile 🚨 崩溃 + open_tab home 卡死**（127 pop 主线程自锁回归，与 125 同款根因）→ ②follow_user、⑦沉浸态、⑧edit_profile 确认弹窗因 open_tab 崩溃无法验证。**v1.4.128 已修 3 项重新打包**（open_tab 崩溃回归/like 合成触摸/search 坐标），触摸盲区留待后续批次。

### [已验证] ⑦ 全屏沉浸播放态卡死（2026-08-27 祥哥反馈「只能重启」）
- **127 装机验证：未完成**（open_tab 崩溃阻断，`_recoverFromImmersive` 内部 pop 调用随 128 一并移除）→ **128 重新验证**
- **现象**：设备进入 TikTok 全屏沉浸播放态——底部导航栏/顶部 For You tab/搜索全部消失，屏幕只剩视频+右上角眼睛/向下箭头图标；**手动点击视频无效、go_back/open_tab 都退不出**，只有重启 App 或手动上滑能恢复
- **根因（三路证据）**：ui_scan 显示 feed cell/feedLikeButton/For You 仍在 a11y 树 → `_isOnFeed` 假阳性 YES → `_gotoHomeFeed` 以为已在首页、深链兜底被短路；实际导航栏被全屏播放器盖住，setSelectedIndex 只切下层
- **v1.4.127 修复**：①新增 `_isHomeChromeVisibleOnMain`（hitTest 验证 a11y_vo_home 是否真可见可点）②新增 `_isHomeFeedUsable`（完整首页判定=在feed+导航栏可见）③新增 `_recoverFromImmersive`（dismiss presented→pop 推入页→点右上角收起箭头→上滑，祥哥实测上滑有效）④`_gotoHomeFeed` 成功判定收紧为 `_isHomeFeedUsable`，沉浸态先退全屏再深链兜底
- **验收**：设备进沉浸态后 `go_home` 应 3s 内自动退出回正常首页（不再需要重启/手动上滑）

### [已备待发→128 已修] ⑥ like 假成功 → 红心点亮真验收
- **现象**：like 命令假成功（下发即返回 success，未验证红心）
- **v1.4.127 修复**：CommandActionLike 改调 `_performLikeSafe`（sendActions 点击），返回红心验收结果
- **127 装机验证：❌ 红心不亮**——sendActionsForControlEvents: 不触发 TikTok 点赞（feedLikeButton 实测不响应），红心未点亮
- **v1.4.128 修复**：`_performLikeSafe` 改用合成触摸 `_safeTapAtPoint:`（XNTouchSimulator 内部 hitTest+sendActions+手势+触摸事件，手动 tap 红心点亮已验证）→ **128 重新验证**

### [已备待发→128 已修] ⑤ open_tab home 无法从 push 的 profile 退出 → 崩溃回归
- **现象**：open_profile 推入个人主页后 `open_tab home` 假成功（setSelectedIndex 只切 tab bar 下层，屏幕仍显示推入的 profile）
- **v1.4.127 修复**：`_tapTab` 切 tab 前先 `_popPushedControllersInWindow`（同步 pop 所有导航栈推入页）
- **127 装机验证：🚨 崩溃/卡死**——`open_tab profile` → 42s 后 CRASH last_action=open_tab（watchdog 杀进程）；`open_tab home` → 命令无响应屏幕冻结。根因=**127 引入的同步 pop 主线程自锁回归**（`_tapTab` 的 dispatch_sync(main) block 内 popToRootViewControllerAnimated: → TikTok VC pop 时内部 dispatch_sync(main) → 主线程自锁，同 125 同款）。**此崩溃阻断批内其余 3 项验证（②⑦⑧）**
- **v1.4.128 修复**：同步 pop 全部移除——①`_popPushedControllersInWindow` 改为 `_hasPushedControllersInWindow`（只检测不执行 pop）②`_tapTab` 检测到推入页且目标 home → `snssdk1233://feed` 深链兜底（TikTok 深链导航替换推入页，不会自锁）③`_recoverFromImmersiveOnMain` 移除 pop 调用 → **128 重新验证**

### [已备待发→触摸盲区] ④ follow 验证假阳性（「Following」子串误判）
- **现象**：follow 命令对已是自己的视频（own-profile 的「2, Following,」计数按钮）误判为关注成功
- **v1.4.127 修复**：新增 `_performFollowVerified`——对比点击前后按钮 label 变化 + 排除 own-profile 计数按钮误判
- **127 装机验证：❌ 未点上**——`state_diag before=after='Follow xo.sleepybrunette' success=False`，**触摸盲区**：TikTok 关注按钮对 XNTouchSimulator 合成触摸不响应（手动 tap (384,333) 也无效果，仅 like button 响应）→ **留待触摸盲区批次**

### [已备待发→触摸盲区] ③ search_keyword 无真实验证
- **现象**：search_keyword 1s 返回 success，未验证是否真的在结果页
- **v1.4.127 修复**：`_performSearchKeyword` 改返回 dict，提交搜索后等 3s + `_isOnSearchResultsOnMain` 验证结果页
- **127 装机验证：❌ 搜不到**——**触摸盲区**：TikTok 搜索按钮（TTKSearchEntranceButton）对合成触摸不响应（tap 两次+双击均失败），且 127 `_performOpenSearch` 坐标 (width-30,65) 偏下。**128 已修坐标**(width-28,42=ui_scan 实测 center 386,42)；触摸盲区本身留待后续批次 → **128 先验坐标修复**

### [已备待发] ② follow_user 用户名深链不导航
- **现象**：follow_user 传用户名时深链不导航，假成功
- **v1.4.127 修复**：`_performFollowUser` 重写——数字 uid 走深链；用户名走「回首页→开搜索→输入→提交→点 Users tab→点用户名行→真实验证关注」
- **127 装机验证：未完成**（open_tab 崩溃阻断；且用户名流程依赖搜索→触摸盲区）→ **128 重新验证 uid 深链段 + 用户名段并入触摸盲区批次**

### [已验证] ① backup_account 安全解档（secure-coded archive 解不开）
- **现象**：backup_account「未检测到登录态」——NSUserDefaults 出现 `NHAccountManager*:data:archive` 新结构（NSKeyedArchiver secure-coded），`unarchiveObjectWithData:` 返回 nil → 候选识别不到
- **v1.4.127 修复**：AccountSwitcher 新增 `_safeUnarchiveData:`（iOS11+ unarchiveTopLevelObjectWithData + @try）+ `_flattenObjectToPlist:`（KVC 反射展平自定义模型，深度6）
- **127 装机验证：✅ 通过**——backup_account 识别到登录态，200+ 字段 KVC 展平备份成功 → **已验证**

## v1.4.128 攒批（3 项修复已编译已打包，装 128 一次验）

> **发版门禁**：127 装机暴露 open_tab 崩溃回归（P0）→ 攒批 3 项修复：①open_tab 崩溃回归（pop→深链兜底）②like 红心不亮（sendActions→合成触摸）③search 坐标修正。已编译打包 `TikTok_XNOW_v1.4.128_BH.ipa`（374.2MB，2026-08-28 12:10 上传 static）→ 装机验证 127 未完成的 3 项（②follow_user uid 段 / ⑦沉浸态 / ⑧edit_profile 确认弹窗）+ 本批 3 项。

### [已修待验] ① open_tab 崩溃/卡死回归（127 pop 主线程自锁）
- **修复**：`_popPushedControllersInWindow`→`_hasPushedControllersInWindow`（只检测）+ `_tapTab` 检测推入页且目标 home → `snssdk1233://feed` 深链兜底 + `_recoverFromImmersiveOnMain` 移除 pop
- **验收**：`open_tab profile` 不崩不卡 → `open_tab home` 深链回 feed（截图非 profile）

### [已修待验] ② like 红心不亮（sendActions 无效）
- **修复**：`_performLikeSafe`/`_waitLikeVerified` retry 统一改合成触摸 `_safeTapAtPoint:`（feedLikeButton center=382,390 手动 tap 红心点亮已验证）
- **验收**：后台「❤️ 点赞」→ message 含红心点亮验收通过

### [已修待验] ③ search 坐标修正
- **修复**：`_performOpenSearch` 坐标 (width-30,65)→(width-28,42)（ui_scan 实测 TTKSearchEntranceButton center=386,42）
- **验收**：open_search 精确命中搜索按钮（state_diag acc_label=搜索按钮类名）

## 🔵 新发现待后续批次（触摸盲区）

> **根因方向（v1.4.128 未修，留待专项批次）**：XNTouchSimulator 对 TikTok 新 UI 部分控件不生效——搜索按钮/关注按钮/头像按钮对合成触摸+UITapGestureRecognizer KVC firing 均不响应，**只有 like button（feedLikeButton）响应**。已验证：手动 tap (382,390) 点亮红心，但 tap (386,42) 搜索 / tap (384,333) 关注均无效果；hitTest 命中正确（state_diag 显示 acc_label 正确）但事件不被消费。**假设**：TikTok 这些控件用 UIControlEventTouchUpInside 之外的响应机制（如内部手势代理、独立 UIControlEventTouchDown 序列）或要求真实多指/长按序列。**方向**：XNTouchSimulator 升级——补 sendActionsForControlEvents:UIControlEventAllEvents / 事件序列时序对齐 / 用 UIControl 直接 sendAction 到 target。

### [待修] 触摸盲区：搜索按钮不响应
- 搜索按钮（TTKSearchEntranceButton center=386,42）对合成触摸不响应（tap 两次+双击失败），127 open_search 坐标也偏
- 128 已修坐标（③），若 128 装机后仍点不开搜索 → 触摸盲区专项批次修

### [待修] 触摸盲区：关注按钮不响应
- 关注按钮（`kAccFollow` 命中但点击无效，state_diag before=after='Follow xo.sleepybrunette' success=False）——label 非 UIControl 合成触摸点不到按钮本体；手动 tap (384,333) 也无效果
- 127 `_performFollowVerified` 已做 label 命中找最近 UIControl 本体 + sendActions + tap 双路径，仍失败 → 需盲区专项

### [待修] 触摸盲区：头像按钮不导航
- feed 头像（AWEStoryAvatarButton）合成触摸不导航；open_profile 深链也失败 → 远程进别人主页不可达（影响 follow_user/collect_fans 等依赖别人主页的功能）
