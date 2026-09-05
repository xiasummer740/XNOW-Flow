# XNOW-Flow 接力开发笔记索引

## 2026-09-05
- [v1.4.150 装机验证完成（A4 账号池同步 + open_tab 假成功盲区）](2026-09-05-v1.4.149-a4-account-sync-opentab-fix.md) — A4 backup 后主动 POST status(current_account)（148 HTTP poll heartbeat 从不触发=根因，走 XNURLProtocol sendMessage 带 secret）**已验证 count=1**；open_tab profile **真成功**（setSelectedIndex after:3 + ui-scan 证在 profile 页，非预期 failed——148 时类名匹配坏，150 好=不稳，下版加落位验证）；回归 6/7(follow 基线搁置)；版本显示回归根因=注入漏传 Config.plist（已修 + 自检 + CLAUDE.md 🔴 规则），150=149 同代码仅升版本号
- [148 全量装机验证 16 项完成](2026-09-05-v1.4.148-full-verification.md) — A 组 3 过 1 新 bug（**A4 B41 账号池同步 FAIL**：设备从不 POST status 账号不上报）、B 组代码层全过、C14 save_video 假成功暴露 + open_tab 非 home tab 假成功盲区；ISSUES 行状态已翻（已验证 16/43/50/55/56/57/71）、3 新待修登记，下批候选= A4/C14/open_tab

## 2026-09-04
- [follow 三层墙证伪 + 拍板搁置](2026-09-04-v1.4.148-follow-blocked.md) — 148 方向 D 装机验证证伪：43.7.0 触摸墙(HID 沙盒拿不到 ContextID ctx=0)/深链墙(全 scheme 忽略)/网络墙(签名未解)挡死 follow 全部路径；**祥哥拍板搁置 follow(方向 E 待特批)，下批对已装 148 跑全量验证清单 16 项(任务 #37)**；关键认知=能自动化的是直调 UIKit 不是触摸

## 2026-09-01
- [zsign DER 修复 + 装机存活验证](2026-09-01-zsign-DER-fix.md) — zsign 签名 SIGTRAP 根因实锤（DER 264→裸 RSA 256）+ 修复版首次装机存活 + net_socket 探针完整数据；**🔴 zsign 重签必须 -z 9（默认不压缩→685MB 大包装不上）** + 最终产物 _xn_z9.ipa
- [v1.4.142 141 闪退根因修复](2026-09-01-v1.4.142-crash-fix.md) — 根因=TikTok Swift 私有类名明文触发反 hook SIGTRAP 自杀；修复=XOR(0x5A)混淆 + **🔴 clang -O2 常量折叠会把解码结果写回 __literals 明文常量池，必须 noinline+volatile 三重防折叠** + XNRequestHooks 改名；142 IPA 已注入上传待装机，装机后验①启动不闪退②net_request 抓包

## 2026-08-31
- [v1.4.138 网络层 Step 0 决定性探针](2026-08-31-v1.4.138-net-layer-step0.md) — installHooks 根因修复生效确认(session 0→10) + TikTok 主 API 疑似不走 NSURLSession(滑 TikTok 期间零命中) + v1.4.138 已构建待装机(registered 读取修复/全局计数/net_sniff 时间盒)；**待装机 138 → net_sniff/net_diag 一锤定音判路线 C/B/A**

## 2026-08-27
- [v1.4.127 攒批修复（7 项假成功/卡死）](2026-08-27-v1.4.127-batch.md) — 备份secure-coded解档/关注/搜索/点赞真验收/退出profile/沉浸态退出+发版门禁装机全量验证硬性落地；装 TikTok_XNOW_v1.4.127_BH.ipa 一次验全批，设备已恢复健康待装机验证

## 2026-08-08
- [v1.4.52 崩溃治理+功能修复长会话](2026-08-08-v1.4.52.md) — 反馈回路打通/点赞/备份/养号/采集，待验证互动养号延迟修复
- [公共用户库交付](2026-08-08-public-users.md) — PPT计划第一批第1项完成，5端点+AI打标+前端页，VPS已上线
- [统一任务引擎](2026-08-08-task-engine.md) — PPT计划第一批第2项完成，运行中任务逐单元下发+风控+状态查询接口

## 2026-08-09
- [设备端环境伪装 set_country](2026-08-09-set-country.md) — 切换国家核心：region/时区/语言/MCC 伪装成目标国，v1.4.53构建成功待装机，出口IP走小火箭

## 2026-08-10
- [v1.4.76 接力](2026-08-10-v1.4.76-接力.md) — 切首页/互动养号不崩/点赞验证/激活治理/硬件UDID尝试/TikTok控件知识库，待v1.4.76装机验证

## 2026-08-11
- [安全审查修复第一批](2026-08-11-安全审查修复.md) — 3专项Agent全面审查+后端4高危已修复部署+设备端掉线根因(轮询无重连)定位，待装机

## 2026-08-14
- [手机当前页实时识别 6 页](2026-08-14-page-recognition.md) — 识别闭环(云端ui_scan缓存+本机8091桥接)+6页签名零误判+首页菜单bug根因(8/12旧包缺检测修复)，待重打包(修复+截图+菜单)

## 2026-08-15
- [手机当前页实时识别 → 13页+自动关注+live修复](2026-08-14-page-recognition.md) — 同文件追加：fan_list第9页+auto_follow_list指令+home误判live根因(直播预览容器TTKLive/AWELive子串误伤，换IESLive专属锚点)+签名库扩13页(comment/live/edit_profile/chat/settings等)，待v1.4.86装机验证
- [v1.4.88 全自动真机验证](2026-08-15-v1.4.88-verification.md) — 命令通道/点赞/搜索/滚动/页面检测✅；4个确认bug(search_keyword卡死拖垮设备🔴、远程导航全失效🔴、评论按屏幕外🟠、任务状态全误报🟠)；采集=0根因=导航坏；证据=VERIFY-REPORT-2026-08-15.md，待授权修P0/P1

## 2026-08-17
- [v1.4.105 升级提示根治+商业化收口](2026-08-17-v1.4.105-upgrade-fix.md) — TikTok升级弹窗根因=构建脚本误改CFBundleShortVersionString(43.7.0→1.4.104)，v1.4.105修复ShortVersion保持不动仅递增CFBundleVersion，真机验证弹窗消失✅；同批带安全点赞真验收/日志商业化/禁锁屏，已提交69792f3

## 2026-08-26
- [v1.4.121全功能验证 + v1.4.123修改资料按钮修复](2026-08-26-v1.4.123-verification.md) — 121远程验证：健康/卡密/备份/智能浏览(104s防闪退)/自动关注(3账号)✅、国家空(等122)；**新抓bug**：修改资料编辑按钮accId=user_info_manage_edit_profile(下划线)匹配label"Edit profile"(空格)失败→坐标点偏→编辑页没开→v1.4.123已修已上传；122+123已备待发(攒批还差1项或祥哥特批)；后端licenses自动重绑已部署；遗留follow_user导航(username深链)失败待修

## 历史
- [v1.4.35 (2026-08-07)](2026-08-07-v1.4.35.md) — 账号检测修复、触摸注入、前端合并
- [v1.4.125 edit_profile 崩溃根因修复（dispatch_sync 主线程嵌套自锁）](2026-08-26-v1.4.125-edit-profile-crash.md) — v1.4.124 装机崩溃(坐标270/438误赋用户名) → 125 坐标修292/523+赋值校验，但装机仍崩(edit_profile:start后死锁)；隔离测 open_tab 稳定 → **实锤根因=外层 dispatch_sync(main) 包 _tapTab 内部 dispatch_sync(main)=主线程自锁→watchdog杀进程**；已修3处(_performEditProfile/_performLogout/_performRegisterAccount)去外层包装+dylib重建上传 TikTok_XNOW_v1.4.125_BH.ipa；**待祥哥装机验证**；同时收齐云控讲解.pptx 98页功能清单→docs/云控功能清单.md(手机/网页分区+缺口对照+三批路线图)
