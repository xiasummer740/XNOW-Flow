# XNOW-Flow 接力开发笔记索引

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
