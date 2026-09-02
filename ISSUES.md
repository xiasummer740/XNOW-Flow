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

## v1.4.128 攒批 → 装机验证结果（2026-08-28）

> **装机验证（2026-08-28）**：装 `TikTok_XNOW_v1.4.128_BH.ipa` 逐项实测。**结果：① open_tab 🚨 仍崩溃（根因升级）→ 129 修复；② like ✅ 已点亮**；③ search 未验证（open_tab 崩溃阻断）。128 全树遍历导致 open_tab 崩溃 → v1.4.129 重建修复（见下方 129 攒批）。

### [已验证→129] ① open_tab 崩溃/卡死回归（128 全树遍历主线程卡死）
- **128 装机实测：🚨 仍崩溃**——`open_tab profile` 13:47:59 polled → 13:50 offline → 13:54:43 `CRASH: [last_action] open_tab`（watchdog 约 7 分钟才杀，比 127 的 42s 慢）。
- **128 根因（再升级）**：127 pop 自锁 → 128 改 `_hasPushedControllersInWindow`（主线程 dispatch_sync(main) block 内**完整 VC 树遍历直到 depth 20**）——对比 `_findTabBarControllerInWindow` 找到 TabBar 浅层提前返回（v1.4.125 稳定），全树遍历本身在主线程跑满 → 卡死 → watchdog 杀。**主线程内任何完整 VC 树递归遍历都是雷**（pop 会触发 TikTok 内部 dispatch_sync(main)，遍历会耗尽主线程）。
- **v1.4.129 根治**：删除 `_hasPushedControllersInWindow`，不再检测推入页。`_tapTab` 步骤 0 改为轻量 `_isHomeFeedUsable`（特征控件查找+hitTest，不遍历完整树）：home 且不在可操作首页 → `snssdk1233://feed` 深链兜底；正常首页走 setSelectedIndex（v1.4.125 稳定路径）。→ **129 重新验证**

### [已验证] ② like 红心不亮（sendActions 无效）
- **修复**：`_performLikeSafe`/`_waitLikeVerified` retry 统一改合成触摸 `_safeTapAtPoint:`（feedLikeButton center=382,390 手动 tap 红心点亮已验证）
- **128 装机实测：✅ 通过**——like 返回「已点赞（红心点亮验证通过）」→ **已验证**

### [已修待验] ③ search 坐标修正
- **修复**：`_performOpenSearch` 坐标 (width-30,65)→(width-28,42)（ui_scan 实测 TTKSearchEntranceButton center=386,42）
- **128 装机实测：未验证**（open_tab 崩溃阻断批内其余验证）→ **129 重新验证**

## v1.4.129 攒批 → 装机验证结果（2026-08-28）

> **装机验证（2026-08-28 14:42）**：装 `TikTok_XNOW_v1.4.129_BH.ipa` 跑回归清单 all。**结果：open_tab 崩溃根治 ✅（129 核心目标达成）；like/follow ❌ 触摸盲区（128 的 like「已验证」是崩溃误判，已纠正）；backup ❌=回归脚本 action 写错（backup→backup_account 已修脚本）；go_home ✅ 18s；open_search ✅ 能进搜索页（已采集到 search 页控件为证）**。

### [已验证] ① open_tab 崩溃根治（128 全树遍历卡死 → 轻量深链兜底）
- **129 装机实测：✅ 通过**——`open_tab profile` 返回 `diag:{method:setSelectedIndex, before:0, after:3}`（v1.4.125 稳定路径，不崩不卡）；`open_tab home` 返回 `diag:{method:not_home_deeplink}`（深链兜底回 feed）；设备全程响应，无 CRASH → **已验证**。128 的 `_hasPushedControllersInWindow` 全树遍历卡死根因已删。

### [已验证→触摸盲区] ② like 红心点亮（128 的「已验证」是崩溃误判）
- **128 的 like「✅ 已点赞」是假阳性，已纠正**（血证）：128 装机时 13:55:27 `state_diag acc_label='Video liked'`（旧视频残留）→ 同一秒 `CRASH last_action=like` → 崩溃重启后回执 `success「已点赞（红心点亮验证通过）」`。**红心实际没点亮**（isSelected=False），success 是崩溃后的误回执。
- **129 装机实测：❌ 真实失败**——like 返回「点赞未生效（未检测到红心点亮）」。touch_diag 显示 tapAtPoint(382,390) 执行、hitTest 命中 AWEFeedVideoButton，但红心不亮。**结论：like 也属于触摸盲区**（之前「只有 like button 响应合成触摸」判断错误）。→ 并入触摸盲区专项批次。

### [已验证] ③ search 坐标修正（128 未验 → 129 验）
- **129 装机实测：✅ 能进搜索页**——设备当前页面已采集为 search 页（AWESearchBar/搜索框/Search 按钮/Trending 列表 64 控件），open_search 坐标 (width-28,42) 命中生效 → **已验证**（后续搜索提交按钮点按属触摸盲区，另列）

### [已验证] ⑦ go_home 沉浸态退出
- **129 装机实测：✅**——go_home duration 18s 返回 success（设备从非首页状态回 feed）→ **已验证**（18s 偏慢待查是否走深链，非崩溃级）

### [脚本 bug 已修] backup_account 回归脚本 action 写错
- **129 装机实测：❌「OK: backup」假成功 = 回归脚本 bug**——CHECKS 发 action `backup`，设备端无此 handler 只回默认 OK。正确 action 是 `backup_account`（11:41 实测返回「已备份账号 #1 登录态」+ country:gb + 200+ profile_keys 真备份✅）。**regression-check.py 已改 backup→backup_account**，下版回归复测。

### [129 未验证] ② follow_user uid 段 / ⑧ edit_profile 确认弹窗
- 127 被阻断项：follow_user 用户名段依赖搜索→触摸盲区；edit_profile 确认弹窗待专项。uid 深链段待复测。

## v1.4.130 攒批 → 装机验证（触摸盲区根治）

> **攒批（2026-08-28 16:33）**：`TikTok_XNOW_v1.4.130_BH.ipa` 已编译打包上传。**本批核心 = 触摸盲区根治**：XNTouchSimulator 升级 IOHIDEvent 真实事件注入（iOS 触摸系统真入口），一个根因解锁 7+ 功能。
> **根因实锤**：KVC 合成 UITouch 的 `_gestureRecognizers` 数组为空 → UIWindow `_sendTouchesForEvent:` 不关联手势识别器 → TikTok 手势收不到事件 → 坐标命中但事件不被消费（全按钮盲区）。
> **方案**：IOHIDEvent digitizer 事件（dlsym 运行时解析私有符号 + IOHIDEventSystemClient 取设备 ContextID）经 `UIApplication _handleHIDEvent:` 注入，UIKit 完整建 UITouch + 关联手势识别器，手势状态机正常跑。符号/ContextID 缺失回退旧 KVC。

> **131 迭代（2026-08-28 16:54）**：130 装机回归 like/follow 仍失败。**touch_diag 证据**：open_search 上报了 touch_diag（而 130 HID 分支在打 diag 前 return）→ **HID 注入降级未生效**（touch_diag 无法区分 129/130 降级，已加设备端上报取证）。131 双管齐下：①`hid_diag` 上报锁死 HID 失败点（符号解析成败 / ContextID 值）②合成 touch 补全 `_gestureRecognizers` 关联（根治真正根因：UIKit `_sendGesturesForEvent:` 按此数组把手势分发给识别器，之前为空 → 手势收不到事件 → 全按钮盲区）。**待重装验证**。

> **132 迭代（2026-08-29 10:13 装机实测 + hid_diag 铁证）**：131 装机后设备 id 漂移 iphone_7098FAE4（i4Tools 重装清 NSUserDefaults/IDFV，硬件 IOPlatformUUID 在 app 沙盒取不到 → IDFV 兜底漂移）→ 卡密浮窗 → **后端 rebind 卡 id=2 到新 id 恢复激活**（已完成）。
> **HID 断点锁定**：tap home tab 坐标 (41,712) 实测上报 `hid_diag data={"msg":"tap_ctx_zero","x":41,"y":712}` + touch_diag `view=TTKTabBarButton gestures=[UITapGestureRecognizer] target_actions=[]`。即：**符号 resolve OK（dlsym 全过）、HID 分支正常进入，唯一断点 = `_hidContextID` 取到 0**。根因判断：`setMatching` 是异步的——服务经 client 内部队列注册，立即 `CopyServices` 常空。
> **132 修复**：`_hidContextID` 客户端缓存复用 + setMatching 后轮询等服务（最多 1.5s）+ ctx 缓存秒回 + `ctx_probe` 诊断上报（服务数/ctx 值，区分「异步时序」vs「沙盒无 digitizer 服务权限」）。**待重装验证**。
> **同时新发现导航 bug（132 顺带修）**：`_tapTab:home` 在 `_isHomeFeedUsable=NO`（非 feed 页）走 `not_home_deeplink` 分支**绕过触摸直接深链** `snssdk1233://feed`，但 4 个深链 scheme（空/feed/main/home）在 profile 页全被忽略 → go_home 4 轮耗尽 return NO 却被默认 success（duration 18s 假成功）。**根因**：129 为防全树遍历崩溃删了推入页检测，深链兜底成了唯一回 feed 路径但深链本身失效。**修复方向**：非 feed 页先真实触摸 tap home tab（a11y_vo_home 就在屏内），失败再深链 + 真实验证。

> **133 攒批发版（2026-08-29 11:13）**：`TikTok_XNOW_v1.4.133_BH.ipa` 已编译打包上传（374.2 MB）。**本批 = 132 全部修复 + 设备 id Keychain 根治**。**132 装不了定位为设备侧**（132 VPS md5=本地 md5=18bce14c...，主二进制 md5 同 131 edcc9c3d，IPA 结构/签名/Info 全一致，非 IPA 损坏——装到一半报错是设备空间/进程/USB）。**Keychain 根治**：XNOWER.m 新增 `XN_KeychainReadDeviceId/XN_KeychainWriteDeviceId`（service=com.xnow.deviceid，kSecAttrAccessibleAfterFirstUnlock），设备 id 生成/恢复后**双写 Keychain**——下次重装 NSUserDefaults 空时先从 Keychain 恢复同一 id，卡密绑定不再失配（旧 DeviceIdentity UID 已弃用，独立 service 互不影响；该注释「Keychain 重装会变」指旧 UID 方案，非本路径）。**待装机验证**：132 的 ctx_probe + tap home 真切换 + 133 Keychain 重装恢复三合一。

### 装机验证清单（逐项实测记 真成功/假成功/崩溃）
1. **like 红心点亮**（回归清单）— 盲区核心
2. **follow 关注**（回归清单）— 盲区核心
3. **search 搜索提交**（回归清单）— 盲区核心
4. **头像 open_profile 导航** — 盲区核心（AWEStoryAvatarButton）
5. **open_tab profile**（回归清单）— acc_id_tap fallback 盲区
6. **go_home 从 profile 页**（导航 bug 一并验）
7. **backup_account**（回归脚本 backup→backup_account 已修，复测）
8. **控件地图 3 页补采**：following / comment / edit_profile（tap 导航解锁后补采）
9. **hid_diag ctx_probe**：上报 ctx 是否非 0（132 HID 修复——setMatching 异步→轮询等服务，区分时序 vs 沙盒无权限）
10. **tap home 真切换**：profile 页发 open_tab home，ui_scan 复验回 feed（132 导航 bug 修复）
11. **Keychain 重装恢复**：本次装机后 133 已双写 Keychain → 下次重装 device_id 不再漂移（根治卡密重输）

## v1.4.134 无障碍点击验证（触摸盲区转向）

> **方向拍板（2026-08-29，祥哥）**：触摸注入三层全拒已实锤（①HID `ctx_probe ctx:0`=沙盒无 digitizer 服务权限 ②KVC 合成触摸 `isHighlighted=False`=UIWindow 拒收 ③直接调 target-action `click` 页面不动）。8-28 白天纯 KVC 已进不去 following/comment/edit 三页，8-27「全链路成功」真伪存疑。**转向无障碍点击**：`accessibilityActivate`（VoiceOver 官方点按路径，完全绕过触摸管线）。TikTok 有完整无障碍标识体系（`a11y_vo_home` 等 12+ 处已采）。
> **实现（v1.4.134）**：新增 `acc_click` 命令（CommandEngine `_performAccClick`）——按 `acc_id`/`label`/`x,y` 定位控件 → 命中 view + superview 链逐一调 `accessibilityActivate` → 上报 `acc_diag`（ok / activated_class / 命中类名）。独立命令不影响 tap 流程。

### 134 装机验证清单（逐项实测记 真成功/假成功/崩溃）
1. **acc_click a11y_vo_home**：profile 页下发 `acc_click acc_id=a11y_vo_home` → acc_diag 看 `ok=true`? → **ui_scan 复验是否切回 feed 页**（验证成功标准 = 页面变化，非返回值）
2. **acc_click a11y_vo_profile**：feed 页反向切到 profile
3. **acc_click user_info_manage_edit_profile**：编辑按钮 → ui_scan 看是否进编辑页（采 edit_profile 地图第 5 页）
4. **acc_click friends**：friends tab → ui_scan 看是否进 friends 页
5. **acc_click 坐标兜底**：`acc_click x=107,y=235`（Following 数字）→ ui_scan 看是否进 following 列表（补采第 6 页）
- **成功判定**：acc_diag `ok=true` 且 ui_scan 页面切换 = 真成功；`ok=true` 但页面未变 = 假成功（activate 返回 YES 但动作未执行）；`ok=false` = 控件未实现 activate（该 acc_id 不可用，换 label/坐标）。

### 134 装机验证结果（2026-08-29 实测，5 项全 ok=false → 无障碍点击路线证死）

| # | acc_click | 命中控件 | activated_class | ok | 页面切换 |
|---|-----------|----------|-----------------|-----|----------|
| 1 | a11y_vo_home | TTKTabBarButton (0,0 82.8x49) | (空) | ❌ false | 无（仍在 profile） |
| 2 | a11y_vo_profile | TTKTabBarButton (331.2,0 82.8x49) | (空) | ❌ false | 无 |
| 3 | friends | TTKTabBarButton (82.8,0) | (空) | ❌ false | 无 |
| 4 | user_info_manage_edit_profile | UIView (0,0 58x30) | (空) | ❌ false | 无 |
| 5 | 坐标 107,235 | TUXLabel (100x23.3) | (空) | ❌ false | 无 |

> **结论（第 4 条死路确认）**：TikTok 的 `a11y_vo_*` 标识控件是自定义 UIView（TTKTabBarButton 等），**未实现 `UIAccessibilityAction` 协议的 `accessibilityActivate`**，返回值恒 NO。VoiceOver 在 TikTok 上可用是因为 TikTok 注册了另一套 accessibility 元素树，不是这些带 `a11y_vo_*` 标记的视图。`hit 控件命中正确`（acc_id 定位没问题）但激活动作全部被拒。
> **四路全死实锤**：① HID `ctx=0` ② KVC `isHighlighted=False` ③ sendAction 无导航 ④ accessibilityActivate `ok=false`。**iOS 沙盒内无法合成触摸或无障碍激活** → like/follow/comment/edit 的自动化不再依赖触摸注入。
> **控件地图 3 页采集路径改为人工导航**：祥哥手动把设备点到 following/comment/edit_profile 页 → `collect-control-map.py` 跑 ui_scan 采集（采集本身不需要触摸）。

## v1.4.135 网络层点赞（交互选 C 纯网络层，祥哥 2026-08-30 拍板「先做点赞」）

> **方向**：触摸四路全死后，点赞/关注/评论/编辑不再依赖 UI，直接构造 TikTok 请求走 app 自身会话（feed 拦截 header 全量复用，含 Cookie/device_id/x-tt-token）→ NSURLSession 发出 → `status_code==0` 才算成功。
> **实现（v1.4.135）**：新增 `net_like` 命令（CommandEngine `_performNetLike:`）——aweme_id 缺省取当前 feed 第一条视频；XNURLProtocol 新增缓存最近 feed 请求 header/URL（`lastFeedRequestHeaders`/`lastFeedRequestURL`）；复用 feed host 拼 `/aweme/v1/aweme/digg/`，form body `aweme_id&digg_type=1&repost=false`。

### 135 装机验证清单
1. **net_like 默认**：feed 首页下发 `net_like`（不带参数）→ 结果 `status=success` 且 response `status_code=0` = 真成功；若 failed，看上报的 `response` body（HTTP 码/status_msg）判断：签名被拒 / 端点不对 / 需要换路径
2. **net_like 指定视频**：`net_like aweme_id=<已知视频ID>` → 同上验证
3. **验证已点**：feed 上该视频红心是否点亮（如果能）→ 或 re-scan 看 is_digg 字段（若可达）
4. **会话材料诊断**：结果里的 `feed_headers_captured` / 上报的 response 帮助定位签名机制

## 🔵 新发现待后续批次（触摸盲区）

### 闪退专项结论（2026-08-29 深挖完成）：两类崩溃，主因是 TikTok 自身 bug
**① 唯一带调用栈的崩溃 = TikTok 自己的后台线程改布局（14:46:11）**
- `NSInternalInconsistencyException: Modifications to the layout engine must not be performed from a background thread...`，`last_action=` 空 = 非指令触发，**空闲自发崩溃**
- **调用栈 0-17 帧无一是我们 dylib**：`objc_exception_throw → CoreAutoLayout ×4 → UIKitCore → MusicallyCore awemeMain ×3（TikTok 主二进制，偏移 4 亿字节处）→ QuartzCore → pthread`。崩溃点在 TikTok 二进制内部，不在注入代码
- 已排除我们 dylib 的后台线程：AccountManager(dispatch_sync 回主线程)、XNOWER 心跳(仅发消息)均安全；`post_video`/publish 指令**从未下发过**
- ❌ **「上传浮层卡死」假设证伪**：`AWEPublishProgressDefaultWrapper`(x=35,y=114,45×60) 在 feed/profile/edit_profile/following/comment **全部 7 页扫描都以同坐标常驻**——是 TikTok 视图树里的常驻休眠 overlay，不是卡死上传。清理发布状态不会修这个崩
- 时间线：14:42:37 following 页扫描完 → 14:44:56 心跳断(offline) → 14:46:11 TikTok 重启后上报 pending 异常。**崩溃发生在扫描后空闲 4 分钟时**

**② 无栈崩溃 = SIGKILL 级（ok+ok 成对，1s 内双启动）**
- 今天 4 段崩溃全部空闲/手工导航时段，无一在执行我们指令；3 段为 `CRASH: ok` 双报（崩溃→iOS 自动重启→无崩溃文件），符合 **jetsam 内存压力杀 / watchdog 杀** 特征（设备 414×736 = iPhone 6/7/8 代低内存，TikTok 内存吃紧）
- 昨天 08-28 的 `last_action=open_tab`×5 崩溃 = **主线程卡死 → watchdog SIGKILL**，v1.4.129 已移除全树主线程遍历修复；今天 open_tab 全过验证修复生效

**结论与方向**：我们指令侧已确认不崩（今天所有指令通过）；闪退主因是 TikTok 自身 bug + 低内存设备压力，**无法从注入侧根治**（栈在人家二进制里）。可选项：①swizzle objc_exception_throw 吞掉此异常（高风险，布局引擎可能已损坏，需祥哥拍板）②崩溃自愈已具备（TikTok 重启→dylib 自动重注入→设备回线）③不主动反复刷新内存重的页面



> **根因方向（v1.4.129 实锤，升级为「全按钮盲区」专项）**：XNTouchSimulator 合成触摸对 TikTok 主要交互按钮**全部不生效**——搜索/关注/头像/like 四个核心按钮都验证不响应（129 like 真实失败实锤；128 like「通过」是崩溃误回执假阳性）。touch_diag 显示 tapAtPoint 坐标正确命中（AWEFeedVideoButton/TTKSearchEntranceButton），hitTest 命中正确，但 UIControlEventTouchUpInside 不被触发。**假设**：TikTok 这些控件要求真实触摸事件链（UIEvent+多个 UITouch + 正确 timestamp/phase 序列），合成 tap 只发单个 touch 不够。**方向（下批专修）**：XNTouchSimulator 升级——①用 IOHIDEvent/私有 API 注入真实触摸事件 ②发完整 touch 序列（Began→Moved→Ended，带正确 timestamp）③或 sendActionsForControlEvents:UIControlEventAllEvents 全事件广播。**此专项是 like/follow/search/头像/follow_user 全部功能的前置解锁，优先度最高。**

> **🚨 触摸盲区影响面扩大到导航命令（129 装机实测 2026-08-28）**：
> ① **open_tab 的 acc_id_tap 方法也盲区**——`_tapTab` 步骤 0 的 `_selectTabByViewControllerClass` 在部分状态下找不到 profile 类（TTKProfileHomeViewController）→ fallback 到 acc_id_tap（合成触摸点 a11y_vo_profile）→ **假成功但 tab 没切**（16:07 实测 open_tab profile 后 ui_scan 仍显示 feed）。用户从 feed 用 open_tab profile 导航不可靠。
> ② **go_home 从 profile 页无效**——16:00 实测：在 profile 页 go_home（duration 18s）后 ui_scan 仍显示 TTKProfileRootView=profile 页，没回 feed；但从 friends 页 go_home（2s）正常回 feed。go_home 在 profile 页走了错误的恢复路径（疑似沉浸态恢复逻辑误判 profile 为需恢复状态）。**导航 bug，下批修**。
> ③ 依赖 tap 点击进入的页面（following 列表 / comment 评论区 / edit_profile 编辑页）在盲区修好前**无法导航采集/操作**。

### 控件基线地图采集进度（2026-08-28 / 08-29）
- ✅ 已采 5 页：feed(63) / search(64) / profile(73) / friends(63) / **following(194)**，汇总 `docs/control-map/control-map-all.md`（一个文件）
- following 页（2026-08-29 人工导航采集，从 VPS 日志恢复）：顶部 `AWESlidingTabButton` 三段式（Following 103 / **Followers 19K 选中** / Suggested）、关系行 `TTKStoryAvatarView`(44,195 68×68)+`AWEAliasEditLabel`(191,186)+`TUXButton Follow`(354,195 88×32)、Back(28,42)、`icEditAlias` 笔标、LIVE 标记 `GBLFeedStaticLiveMarkView`。⚠️ 实际选中是 **Followers** 页签（「Only rocky_teenager can see all followers」横幅印证），但关系列表 UI 结构与 Following 相同，锚点可用
- ⚠️ 采集时设备闪退：ui_scan 扫完 210 元素后 app 崩溃（WS 断连）。页上 `AWEPublishProgressDefaultWrapper`(x=35,y=114) 后来确认是**全部 7 页常驻的休眠 overlay**，与闪退无关（闪退= T ikTok 后台线程改布局 bug，见上方专项结论）
- ✅ **7 页全齐（2026-08-29）**：feed(63) / search(64) / profile(73) / friends(63) / following(194) / **comment(189)** / **edit_profile(54)**，共 700 控件 → `docs/control-map/control-map-all.md`
- comment 页（2026-08-29 采集）：评论列表 `UITableView TTKCommentListViewComponent`、关闭按钮 `UIButton(388,227)`、排序 `Sort Option(344,227)`、评论行（TTKCommentAvatarView/TUXLabel username/YYLabel 文本）、点赞 `TTKCommentAnimatedButton(330,385)`、踩 `TTKCommentDislikeAnimatedButton(390,385)`、输入框 `AWEGrowingTextView "Add comment"(170,708)`、发表 `TUXButton CommentInputSendButtonViewComponent(416,708)`、表情/@ 按钮
- edit_profile 页（2026-08-29 采集，视觉确认=编辑资料表单）：Back(28,42)、头像 `BDImageView(151,130)`、行锚点（Name y=291 / Username y=343 / Bio y=391 / Pronoun y=484 / Links y=562 / Fundraiser y=610，均为 UITableViewCell 行）；⚠️ 字段名在子 label 未被 ui_scan 捕获，行锚点可用但字段名要对照视觉截图
- 🔧 修复 collect-control-map.py 两个 bug：①等待条件从「见 result: 即停」改为「见 `ui_scan: N elements` 元素上报 + 日志稳定」——元素行在 result 之后才落地，旧逻辑白扫；②坐标正则 `x=(-?[\d.]+)` 支持负数（following 页 tab bar 滑出屏外 x=-373）
- **采集数据恢复技巧**：ui_scan 扫完设备若闪退，UI 行已完整落在 server.log，可从日志 `grep 'UI \['` 恢复，无需重扫（following 页即如此恢复）

### [待修] 触摸盲区：like 按钮不响应（129 实锤，128 误判已纠正）
- feedLikeButton (382,390)：129 真实失败「点赞未生效」，128「已点赞」是崩溃误回执（CRASH 后 success + acc_label 残留），isSelected=False 红心未亮
- 127 sendActions 不亮 / 128 合成触摸也不亮 → 需要真实触摸注入

### [待修] 触摸盲区：搜索按钮不响应
- 搜索按钮（TTKSearchEntranceButton center=386,42）：128 坐标修正后能**进搜索页**（open_search ✅），但**搜索提交按钮**（TTKSearchPressStatusButton 374,42）与搜索框输入是否生效待验（129 未测提交搜索）；若提交也盲区 → follow_user 用户名流程仍不可达

### [待修] 触摸盲区：关注按钮不响应
- 关注按钮（`kAccFollow` 命中但点击无效，state_diag before=after='Follow xo.sleepybrunette' success=False）——label 非 UIControl 合成触摸点不到按钮本体；手动 tap (384,333) 也无效果
- 127 `_performFollowVerified` 已做 label 命中找最近 UIControl 本体 + sendActions + tap 双路径，仍失败 → 需盲区专项

### [待修] 触摸盲区：头像按钮不导航
- feed 头像（AWEStoryAvatarButton）合成触摸不导航；open_profile 深链也失败 → 远程进别人主页不可达（影响 follow_user/collect_fans 等依赖别人主页的功能）

## v1.4.143 攒批（网络层点赞第一波 + 免卡密 + TLS 探针，2026-09-01）

> **背景**：祥哥拍板方向 1→3→2（①net_like 会话凭据构造 → ③TLS 栈诊断探针 → ②SwiftNIO 请求层深挖）。
> **net_like 基石证伪（2026-08-31 实测）**：`feed_headers_captured: 0` + 无 aweme_id——feed 走 SwiftNIO 自研栈，完全不经过 URLProtocol/NSURLSession，header 缓存全空 → 原方案依赖的 feed header 数据源不存在。
> **改造数据源（2026-08-31 dump_login 实证）**：设备已登录（`isLoggedIn=True method=cookie`），NSHTTPCookieStorage 有 `.tiktokv.com/.tiktok.com/.tiktokw.us` 等 6 域 cookies：`install_id`/`msToken`/`odin_tt`/`ttreq`/`store-idc`/`store-country-code=us`；`uid_tt` 当前为空。
> **TLS 探针动机（方向3）**：SSL_write/SSL_read fishhook 0 命中（BoringSSL 静态链接推断）→ dlsym 探针定事实。

### [已修待验] ① net_like 改造：真实 host + 会话 Cookie + UA 伪装 + 端点纠正（v1.4.143b）
- **改了什么**（CommandEngine.m `_performNetLike:`）：
  ① diggHost 默认 `api.tiktokv.com` → **`api16-normal-useast5.tiktokv.us`**（net_socket SNI 实锤真实主 API 节点）
  ② headers 不再依赖空 feed header：新增 `_captureTikTokCookieHeader`（NSHTTPCookieStorage .tiktok 域全量拼 Cookie header，含 install_id/msToken/odin_tt）+ `_tiktokAppUserAgent` 伪装 UA
  ③ 结果附诊断：`cookie_count`（拼了几个 cookie）+ `feed_headers_captured`
- **143 装机实测（2026-09-01）**：`cookie_count=9` ✅ 会话 Cookie 提取成功；HTTP 200 到达 TikTok 服务器；但返回 `status_code:1 "Url does not match"` → **端点错误**。查证真实 digg 端点是 `/aweme/v1/commit/item/digg/`（非旧 `/aweme/v1/aweme/digg/`），参数 `type=1&channel_id=0&enter_from=homepage_hot`（非 `digg_type`）→ **143b 纠正**
- **验收**：feed 下发 `net_like`（带/不带 aweme_id）→ `status=success` 且 response `status_code=0` = 真成功；若仍失败看是「参数错误」还是「签名拒」（区分业务层/签名层）
- **已知风险**：TikTok 签名通常还需 X-Bogus/_signature（msToken 只是签名链一环），纯 Cookie 可能仍被拒 → 拒了就归入方向②（SwiftNIO 请求层深挖）

### [代码+部署已验证→无卡端到端留待] ② 后端调试期免卡密开关（licenses.py，2026-09-01）
- **改了什么**：`check_device_license` 加环境变量开关 `XNOW_LICENSE_DEBUG_FREE`——`true` 时直接返回 `licensed:true plan=debug`（365 天），跳过查库
- **控制权在服务端**：用户绕过不了（设备端无感知），商业化时关掉环境变量即恢复卡密
- **部署验证（2026-09-01）**：✅ licenses.py 上传 VPS + systemd 加 `Environment=XNOW_LICENSE_DEBUG_FREE=true` + 重启 active + **进程环境变量确认注入**（/proc/PID/environ 见 XNOW_LICENSE_DEBUG_FREE=true）+ 设备 poll/授权检查 200 OK 正常
- **已知限制**：当前设备 DB 有旧卡（7YDYWY rebind），端到端「无卡设备不输卡密直接激活」需无卡设备验证——留待新设备/商业化前清卡后测（免卡密代码在 DB 查询前 return，优先级最高，逻辑确定）

### [已验证→方向②定路] ③ TLS 栈诊断探针（SocketHooks `tlsProbe`，v1.4.143）
- **改了什么**：新增 `+[SocketHooks tlsProbe]`——`dlsym(RTLD_DEFAULT, "SSL_write"/"SSL_read"/"SSL_get_fd"/"SSLWrite"/"SSLRead")` 查符号是否在动态符号表 + `orig_SSL_write` 是否重绑成功 + 定性 note；net_socket 结果附 `tls_probe`
- **143 装机实测（2026-09-01）**：`SSL_write=0x102b58d08`（**非 NULL，在动态符号表**）+ `orig_SSL_write=SET`（fishhook 已重绑）但 0 命中 → **note 定性：调用点不走 PLT，TikTok 主二进制内部 BL 直调**
- **结论更新**：❌ 旧假设「BoringSSL 静态链接未导出，fishhook 够不着」被推翻 → ✅ 真相反而是符号导出 + fishhook 重绑成功但**同二进制内部直接 BL 调用不经 GOT/PLT** → fishhook 只改表改不到直调点。SSL 明文层 fishhook 路线终结，**方向②（SwiftNIO 请求层内嵌/请求模型深挖）为唯一剩路**
- **附带证据**：net_socket 时间盒抓到真实连接（146.75.94.73=p19-common 签名服务、unknown 3.6MB/23.211.177.233 2.4MB=媒体流），SSL body 密文，SNI 明文可读

### 143 装机验证清单（逐项实测记 真成功/假成功/崩溃）
1. **net_like**：feed 下发 → **实测（143）**：`cookie_count=9` Cookie 提取成功 + HTTP 200 到达服务器 + `status_code:1 "Url does not match"` = **端点错** → 143b 纠正为 `/aweme/v1/commit/item/digg/` + `type=1&channel_id=0&enter_from` 参数 → **143b 待装复验**
2. **免卡密**：设备重装（i4Tools 清空重装模拟新设备）→ 不再输卡密直接激活。**143 实测**：部署+进程 env 确认+授权 200 OK ✅（无卡端到端留待新设备，见上方限制）
3. **net_socket**：下发 → **实测（143）**：`tls_probe SSL_write=0x102b58d08` 非 NULL + orig SET = 内部 BL 直调不走 PLT（方向3 完成，结论更新见上）
4. **dump_login**：**实测（143）✅**：cookies 完整（install_id/msToken/odin_tt/ttreq 多域）+ total_keys 284 + login 正常，与 net_like cookie_count=9 交叉一致，无回归

### [已验证→三层封死，方向②探到尽头] ④ 方向2 SwiftNIO 请求层深挖（net_classes，2026-09-02）
> **背景**：方向 1 net_like 纯手写到签名层边界（HTTP 200 空 body），方向 3 证明 BoringSSL 静态 BL 直调 fishhook 够不着。方向 2 = 深挖 SwiftNIO/Pumbaa 请求层，找主请求模型，目标「能抓完整请求（含签名）就复刻，或直接复用它的发送」。
> **探查手段**：下发 `net_classes` 命令 dump 网络相关类结构（props/methods/ivars），两次全量 150 类。

- **net_classes 全量结果（150 类，2026-09-02 设备实测）**：
  - **PumbaaNetworkCore 主引擎 6 类**（`NetworkEngineUnit`/`NetworkSandboxUnit`/`NetworkModifyAction`/`NetworkDropAction`/`NetworkTaskStatusLog`/`NetworkPerformanceTrack`）→ props=[] methods=(空) **全纯 Swift**
  - **业务 NetworkService 全部**（`TikTokExploreImpl.ExploreNetworkService`/`ExploreSearchNetworkService`/`TikTokPOIImpl.POIReviewsNetworkService`/`TikTokRaven.RavenNetworkImpl`/`TikTokUserCenterImpl.ReportProblemNetworkService`/`TikTokCLAImpl.C24yNetworkService`/PIPOWallet*NetworkService 等）→ props=[] methods=(空) **全纯 Swift**
  - **NIO 底层**（`NIOPosix.Socket`/`NIORawSocketBootstrap`/`NIOHTTP1.HTTPRequestEncoder`/`NIOCore.NIONetworkInterface` 等）→ **全纯 Swift**
  - **唯一 ObjC 暴露完整请求模型 = `PNSFoundationImpl.PNSNetworkHTTPFilterRequest`**（props: `httpMethod`/`url`/`httpBody`/`allHTTPHeaderFields` + 11 个 @objc 方法）→ 但此前实测 calls=0（**非主路径**，PNS filter 仅插件化过滤机制用）
- **方向②结论（三层纵深，注入面全部切断）**：
  1. 业务层 NetworkService（ObjC runtime 可见类名但 props/methods 空）→ **纯 Swift 非 @objc 动态派发，method swizzle/KVC 全无效**
  2. 传输引擎 PumbaaNetworkCore + SwiftNIO → 同上，纯 Swift 不可 swizzle
  3. TLS 层 BoringSSL → 静态编译 + 内部 BL 直调（方向③已证），fishhook 明文层不可达
  → **「抓 TikTok 完整请求明文 / 复用其发送」的设备端注入路线 = ObjC 注入面 + fishhook 注入面双封死**，方向②探到技术尽头
- **net_like 网络层物理极限（三方向汇合定论）**：纯手写请求（net_like）在 TikTok 签名层（X-Bogus 族）被拦截（HTTP 200 空 body）是**注入面能到的极限**；想过签名层只剩两条路：**离线复刻签名算法**（后端/本地实现 X-Bogus，风险=43.7.0 可能已升级签名体系）或 **UI 模拟真实点赞链路**（acc_click 屏内点击复用 TikTok 自身签名，但只能赞当前屏上视频，非任意 aweme_id）

### [进行中→待装复验] ⑤ 签名复刻第一测（祥哥拍板后端签名复刻，v1.4.143c）
> **前置侦察（2026-09-02 WebSearch）**：TikTok 双签名管道——**Web 管道=X-Bogus**（浏览器用），**Mobile 管道=Metasec 四件套 X-Argus/X-Gorgon/X-Ladon/X-Khronos**（App 用）。我们的 digg 走 `api16-normal-useast5.tiktokv.us` = **Mobile 管道** → 缺的不是 X-Bogus 而是 **X-Argus 家族**（旧 ISSUES 假设「缺 X-Bogus」需纠正）。
> **现成库侦察**：douyin-sign（纯 Python，SIMON/AES/RC4 全家桶 + nightly CI 提常量）/ armxe-tiktok-api（Metasec 四件套，2026-03 更新）——**两者都是 Android 组装**（douyin 硬编码 app_id=1128 + googleplay 渠道 + SM-G973N 示例），**iOS 43.7.0 无现成签名实现**。
> **预实验（VPS，2026-09-02）**：douyin-sign 四件套生成成功（X-Khronos/X-SS-STUB/X-Gorgon/X-Argus），但**假设备身份 + 数据中心 IP + 无 cookie** 发 digg = HTTP 200 空 body（与无签名一致）→ 预期内，无法区分「算法无效」vs「缺真实设备身份」。

- **143c 改了什么**（CommandEngine.m/.h，2026-09-02）：
  ① 新命令 `cookie_dump`：回传 `_captureTikTokCookieHeader` 全串 + install_id/msToken 值（签名实验取真实设备凭据，debug 用）
  ② `net_like` 支持 params.`extra_headers`（dict）：合并后端预生成签名头（X-Argus 家族），extra 优先覆盖同名 + Cookie 用 extra 的保证签签一致；附 `sign_headers_used` 诊断
- **验证流程（装 143c 后）**：① 下发 `cookie_dump` 拿真实 Cookie/install_id → ② VPS douyin-sign 用真实凭据生成四件套（aid 试 1233/1128）→ ③ 下发 net_like 带 extra_headers → ④ 看 200 空 body 是否变业务响应
- **判据**：200 空 body 变化（有业务 JSON/错误码）→ 签名有效，接入后端正式签名链路；仍空 → iOS 组装差异/更深风控，**签名复刻正式止损** → 转 UI 模拟点赞收口（见④定论）
