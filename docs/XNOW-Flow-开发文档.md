# XNOW-Flow 开发文档

> **当前技术总览** | 整理于 2026-09-02 | 对应构建版本 **v1.4.143c**
> 面向对象：接手本仓库的开发者 / 祥哥做技术回顾
> 本文描述**现状**（代码实际长什么样），不追叙历史规划。完整功能规划见 `docs/TK云控系统-完整项目实施计划书.md`（旧版文档）。

---

## 1. 一句话说明

XNOW-Flow 是一个 **TikTok iOS 云控系统**：把自研的 `xnower.dylib` 注入到 TikTok iOS 包（BH 版 43.7.0），让每台 iPhone 成为「云控设备」，由网页后台通过 WebSocket/HTTP 下发指令，dylib 在手机端**模拟真实用户操作**（点赞/关注/评论/私信/养号/采集等），并把结果回传。

三端分工：

| 端 | 位置 | 技术栈 | 职责 |
|---|---|---|---|
| **iOS 注入层** | `ios-plugin/xnow-dylib/` | Objective-C / dylib 注入 | 跑在手机里，执行命令、模拟操作、抓包 |
| **后端** | `backend/` | Python FastAPI / SQLAlchemy / SQLite | 下发命令、账号体系、任务调度、鉴权 |
| **网页后台** | `login/` (React) + `backend/static/` (静态页) | React 19 + Vite 8 / TS | 操作界面：设备控制、账号库、数据看板 |

构建链路：**VPS 交叉编译 dylib → 注入 IPA → zsign 重签 → 装机验证**。

---

## 2. 系统全景

```
┌─────────────── 网页后台 (浏览器) ───────────────┐
│  login/ React SPA（React19+Vite8，产物→后端dist兜底）│
│  backend/static/ 静态页（control.html 设备控制等）  │
└──────────────────────┬─────────────────────────┘
                       │ HTTPS / API
┌──────────────────────▼─────────────────────────┐
│  后端 FastAPI (backend/)  — VPS 192.129.210.52   │
│  · 鉴权：JWT 用户登录 + X-Device-Secret 设备鉴权    │
│  · 26 个 API 路由组（设备/账号/任务/素材/反馈...）    │
│  · WS 长连接 + HTTP 轮询 双通道 下发命令             │
│  · SQLite + SQLAlchemy 数据落库                   │
└───────┬────────────────────────┬────────────────┘
        │ WS (ws://...:8000)     │ HTTP 轮询兜底
┌───────▼────────────────────────▼────────────────┐
│  iOS 设备 ×N（BH 版 TikTok + xnower.dylib）       │
│  · XNStartup +load 双层启动 → 建连后端             │
│  · CommandEngine 执行命令（点赞/关注/采集/养号）     │
│  · 三层网络拦截：ObjC swizzle / NSURLProtocol /    │
│    fishhook C 符号重绑 — 抓 TikTok 请求拿签名/数据   │
└─────────────────────────────────────────────────┘
```

---

## 3. iOS 注入层（`ios-plugin/xnow-dylib/`）

### 3.1 文件地图

| 文件 | 职责 |
|---|---|
| `XNStartup.m` | 入口：`+load` 时双层启动（`start()` + 备胎路径），保证必装 |
| `XNOWER.m` | 主控制器：配置读取、命令分发、浮窗面板逻辑 |
| `CommandEngine.m` | **命令引擎（~5600 行）**：60+ 命令的动作执行、状态判断 |
| `XNFloatingPanel.m` | 屏幕上的悬浮菜单（点开可手动触发命令/看状态） |
| `WsClient.m` | WebSocket 客户端：连后端、收发 JSON 命令、心跳 |
| `TikTokHooks.m` | **第一层拦截**：ObjC runtime swizzle + NSURLProtocol 抓 HTTP |
| `XNURLProtocol.m` | NSURLProtocol：拦 TikTok 网络请求 / 回传数据 piggyback |
| `SocketHooks.m` + `fishhook.c` | **第二层拦截**：fishhook 重绑 socket 层 C 符号，抓自研网络栈 |
| `XNRequestHooks.m` | **第三层拦截**：hook PNS 请求模型 setter（抓 Swift 自研栈请求明文） |
| `AccountManager.m` / `AccountSwitcher.m` | 账号管理 / 切换账号 |
| `AccountPool.m` / `AccountSnapshotter.m` | 账号池 / 快照备份 |
| `DeviceIdentity.m` / `DeviceStatus.m` | 设备身份（UDID）/ 设备状态 |
| `CountryEnv.m` | 环境伪装（region/时区/MCC） |
| `XNTouchSimulator.m` | 合成触摸：模拟真实点击（IOHIDEvent 注入） |
| `XNWindowHelper.m` | 窗口/视图查找辅助 |
| `XNOWER.h` / `CommandEngine.h` 等 | 各模块头文件 |
| `Config.plist` | 构建时嵌入的配置（服务器地址、心跳间隔等） |
| `Makefile` | ⚠️ **已过时**，真实构建走 VPS 脚本（见 §6.1） |

> 注：`SocketHooks.m` / `fishhook.c` / `fishhook.h` 目前在 git 中为未跟踪状态（尚未提交），但**构建会编入**——改代码注意别漏提交。

### 3.2 命令全集（`CommandEngine.m` actionFromString）

命令分三类：**操作类 / 采集类 / 调试网络类**。

**操作类：**
| 命令 | 动作 |
|---|---|
| `like` / `net_like` | 点赞（UI 模拟 / v1.4.135 起纯网络层） |
| `follow` | 关注 |
| `comment` | 评论 |
| `collect` | 收藏 |
| `open_profile` / `open_search` / `open_user` / `open_video` | 页面跳转 |
| `go_home` / `go_back` / `open_tab` | 回首页 / 返回 / 切 Tab |
| `switch_account` / `logout` / `register_account` | 账号切换/登出/注册 |
| `send_dm` / `send_card` / `share_live` | 私信/卡片/直播分享 |
| `post_video` / `save_video` / `share` | 发视频 / 存视频 / 分享 |
| `edit_profile` | 改资料 |
| `batch_like` / `batch_follow` / `batch_comment` | 批量操作 |
| `smart_browse` / `nurture_tick` / `nurture_stop` | 智能浏览 / 养号 tick / 停养号 |
| `refresh` | 下拉刷新 |
| `check_health` | 健康检查 |
| `tap` | v1.4.124 坐标点击（x/y） |
| `screenshot` | 截图 |

**采集类：** `collect_fans`（粉丝）、`collect_videos`（视频）、`collect_comments`（评论）、`collect_live_users`（直播观众）、`collect_likes`（点赞用户）、`collect`、`get_account_info`、`report_account`。

**调试/网络类**（v1.4.135~143c 新增，抓 TikTok 网络层）：
| 命令 | 用途 |
|---|---|
| `net_diag` | v1.4.136 网络路径探针（请求走哪条路） |
| `net_sniff` | v1.4.138 时间盒抓包（N 秒记录所有请求） |
| `net_classes` | v1.4.139 网络类内省 |
| `net_socket` | v1.4.140 socket/TLS 双层钩子抓真实请求明文 |
| `net_request` | v1.4.141 hook PNS 请求模型 setter 抓请求明文 |
| `cookie_dump` | v1.4.143c 回传会话 Cookie（签名复刻实验取真实凭据） |
| `ui_scan` | 扫描当前页控件（accId/label/坐标，用于控件基线地图） |

### 3.3 三层网络拦截原理（本系统核心创新）

TikTok 请求分两种路径，拦截必须分层：

```
TikTok API 请求
  │
  ├─ 路径 A：走系统 URL Loading System（NSURLSession）
  │    └→ XNOWURLProtocol（TikTokHooks.m 注册）→ 能拿到 HTTP 明文
  │
  └─ 路径 B：走 Swift 自研网络栈（Pumbaa/PNSFoundation，字节自家实现）
       └→ TLS 层不透出明文（net_socket 实锤）
           └→ 退路：hook 请求模型 PNSNetworkHTTPFilterRequest 的
              setter IMP → 在构造请求瞬间拿 URL/method/headers/body（net_request）
```

- **第一层 ObjC swizzle**（`TikTokHooks.m`）：替换 NSURLSession 相关方法 + 注册自定义 NSURLProtocol。
- **第二层 NSURLProtocol**：`XNOWURLProtocol`（拦 TikTok API）+ `XNURLProtocol`（piggyback 通信通道）。
- **第三层 fishhook**（`SocketHooks.m` + `fishhook.c`）：`fishhook` 重绑 socket 层符号，抓 TLS 之前/之后的原始流量。
- **第四层（兜底）** `XNRequestHooks.m`：hook 自研请求模型的 setter，拿请求明文。

> v1.4.141~142 探索结论：TikTok 主 API 走 Swift 自研栈，TLS 层拿不到明文；net_request 用「替换 setter IMP」在构造瞬间拿到请求模型属性——这是「纯网络层做点赞/发帖」路线的基础。**v1.4.143c 后该路线止损**：douyin-sign 的抖音常量解不开 TikTok iOS 43.7.0 签名（见 §10 版本史）。

### 3.4 网络安全坑（必须遵守）

> ⚠️ **v1.4.142 起**：TikTok 私有类名**禁止明文写进 dylib**——Swift 私有类名明文触发 TikTok 反 hook 检测 SIGTRAP 闪退（141 闪退根因）。代码里私有类名做了 **XOR 运行时解码** + `noinline` + `volatile` 防 clang 常量折叠。新增 hook 代码时同样处理。

### 3.5 已知问题（写代码时注意）

| 问题 | 位置 | 状态 |
|---|---|---|
| `XNRequestHooks.m` 第 13 行 `#import "PnsRequestHooks.h"` 文件名已过时（类已改名 XNRequestHooks） | `XNRequestHooks.m:13` | ⚠️ 本地/history 无此文件，仅靠 VPS `/root/xnow-build/` 残留同名旧文件兜底编译通过；**清空 VPS 构建目录后下次构建会失败**。应改为 `#import "XNRequestHooks.h"` |
| `SocketHooks.m`/`fishhook.c`/`fishhook.h` 未 git 跟踪 | git status | 构建依赖它们，改代码勿漏提交 |

---

## 4. 后端（`backend/`）

### 4.1 技术栈与结构

```
backend/
├── main.py               FastAPI 入口：注册 26 个路由组 + SPA 兜底 + 启动 tick
├── config.py             配置（SECRET_KEY/上传限制等）
├── database.py           SQLAlchemy 引擎 + 建表（SQLite）
├── crypto.py             加解密（账号凭证等）
├── dependencies.py       鉴权依赖（JWT 用户 / 设备 secret）
├── connection_manager.py 设备连接管理（WS 长连 + HTTP 轮询双通道）
├── geoip.py              IP 归属
├── seed.py               种子数据
├── routers/              26 个 API 路由组（见下）
├── models/               SQLAlchemy 模型（20+ 表）
├── schemas/              Pydantic 校验
└── static/               静态前端产物（control.html 等）
```

### 4.2 鉴权双轨

| 对象 | 鉴权方式 |
|---|---|
| **网页后台用户** | JWT（`/api/auth/login`） |
| **iOS 设备** | `X-Device-Secret` header + UUID 校验，恒定时间比较（防时序攻击）；SECRET_KEY 无默认值，未配置启动即抛错 |

### 4.3 API 路由组（26 个）

`auth` 登录 · `devices` 设备 · `dashboard` 看板 · `accounts` 账号 · `tasks` 任务 · `task_executions` 执行 · `timed_tasks` 定时任务 · `device_commands` 命令下发 · `feedback` 反馈 · `announcements` 公告 · `reply_templates` 回复模板 · `media` 素材 · `collected_data` 采集数据 · `execution_stats` 执行统计 · `materials` 素材库 · `video_posts` 发帖 · `dm_tasks` 私信 · `nurture` 养号 · `quick_commands` 快捷指令 · `licenses` 卡密 · `udid` 装机登记 · `public_users` 公共用户库 · `proxy_nodes` 代理节点 · `translate` 翻译 · `adverts` 广告 · `ws` WebSocket 通道。

### 4.4 命令下发链路（核心）

```
网页后台点「点赞」→ device_commands API → connection_manager
    → 设备在线？─是→ WS 推送 JSON 命令给 device_id
                   └否→ 记任务，等设备 HTTP 轮询时取走（HTTP 兜底）
设备执行 → 结果回传（WS 或 HTTP）→ 落库 task_executions
```

### 4.5 已知安全改进（已落地）

- SECRET_KEY 无默认值（防 dev 密钥进生产）
- 上传限制 10MB + 拒绝 SVG（防存储型 XSS / DoS）
- 任务/定时任务非 admin 校验设备归属（防跨租户下发）
- 设备 secret 走 header 不走 URL（防明文进日志）
- ⚠️ **待修**：uvicorn:8000 公网明文（无 TLS）→ 需 nginx 443 + 设备改 https

---

## 5. 网页后台

两套入口并存：

| 入口 | 位置 | 说明 |
|---|---|---|
| **React SPA** | `login/`（React 19 + Vite 8 + TS） | 完整管理后台：账号库/任务/设备/素材/公共用户库等 20+ 页面。构建产物 `login/dist`，部署时拷到后端由 SPA 兜底路由服务 |
| **静态页** | `backend/static/` | 轻量页：`control.html` 设备控制、`install.html` 装机引导、`ws-test.html` 测试。无需构建，直接改 |

> 注：`login/xnow-login/` 是嵌套的重复副本（疑似历史误提交），**以 `login/` 为准**；确认无用后应清理。

### React SPA 页面清单（`login/src/pages/`）

设备管理 · 设备控制（DeviceControl，逐设备下发命令/养号开关）· 账号管理 · 公共用户库（PublicLibrary）· 任务列表 · 定时任务 · 任务日志 · 执行统计 · 素材库 · 卡片管理 · 媒体管理 · 视频管理 · 采集数据 · 反馈 · 回复配置 · 公告 · 广告管理 · 用户管理 · 设置 · 使用指南。

### 前端改动注意事项

- 技术栈：React 19 + Vite 8 + TypeScript ~6.0，**无 axios**（用原生 fetch）、**无 router 库**（手写状态切换）。
- `Button/Card/Input` 等组件必须定义在**组件函数体外**（模块顶层）——曾因定义在组件体内导致每次渲染重挂、输入框丢字符/按钮跳动（v1.4.119 修复血证）。

---

## 6. 构建 → 注入 → 装机全流程

### 6.1 编译 dylib：`build-vps-dylib-143c.py`

```
本地源码 ios-plugin/xnow-dylib/
  → SFTP 上传到 VPS /root/xnow-build/
  → clang-16 交叉编译（target arm64-apple-ios16.5, -fobjc-arc, -Wno-everything）
      编译所有 .m（除 MinimalTester.m）+ 所有 .c → 逐个 .o，任一 error 即失败
  → ld64.lld 链接 → xnower.dylib
  → python3 convert_cmds.py（私有命令转标准命令）
  → 下载回 build-artifacts-ci/xnower-143c/
```

> ⚠️ VPS 构建目录 `/root/xnow-build/` **只 mkdir 不清理**——残留旧文件可能掩盖改名问题（见 §3.5）。改文件后建议清目录重编验证一次。
> ⚠️ `Makefile` 已过时（SRCS 缺 SocketHooks.m/fishhook.c 等），**不要用 Makefile**，用 VPS 脚本。

### 6.2 注入：`.tmp-inject-143c.py`

```
xnower-143c.dylib → 上传 /root/xnow-build/
  → /opt/xnow-flow/vps-inject.py <base_ipa> <dylib> <out.ipa>
      （VPS 无 43.7.0 原始包，以 static 最新已注入 IPA 连续注入）
  → zsign 重签（必须 -z 9！否则包从 374MB 膨胀到 685MB，iPhone 装到 74% 卡死）
  → 下载回 TikTok_XNOW_v1.4.143c_BH.ipa
```

### 6.3 装机

| 方式 | 场景 |
|---|---|
| **爱思助手拖拽** | 主力（本地装大 IPA）。pymobiledevice3 装 700MB+ 大包在 Windows 会卡死（installd 无活动） |
| 爱思卡死时 | 杀 i4Tools/i4Service/i4ToolsService 重启（设备 USB 不受影响） |
| **装机验证** | 一次装机验全批：按「装机验证清单」逐项下发命令实测，每项记 ✅真成功 / ❌假成功 / 🚨崩溃 |

### 6.4 发版门禁（攒批）

- 修复阶段不打包；攒够 **≥3 项「已修待验」** 才编译打包
- 装机=全量验证：不许只验当前 bug，验全部「已修待验+待修+本次新修」
- 发版前必跑 `python regression-check.py all`（open_tab/like/open_search/follow/go_home/backup 六条，三态验收 ✅/❌/🚨），任一 🚨 或 ❌ 核心项 → 不发版先修

---

## 7. 控件基线地图（`docs/control-map/`）

根治「锚点靠猜」：修任何控件问题前，先查 `docs/control-map/`（ui_scan 采集的 accId/label/坐标）。

- 覆盖页面：feed/comment/edit_profile/following/profile/current_state/search 等 8 页（`.md` 人读 + `.json` 机读）
- TikTok 更新后：`python collect-control-map.py <页面>` 重采，对照 diff 看锚点漂移
- 历史教训：`open_tab` 假成功 / `like` 崩溃误判 → 曾因控件漂移误诊，实为触摸盲区/导航链问题——**修问题先确认根因，别急着归因控件漂移**

---

## 8. 踩坑精华（血证集）

| # | 坑 | 对策 |
|---|---|---|
| 1 | **zsign 重签不压缩**（默认 zip_level=0）→ 包 374MB 膨胀 685MB → iPhone 8 Plus 装 74% 卡死 | 重签必须 `-z 9`，回到 ~391MB。修复版 zsign 在 `C:\Users\Administrator\Downloads\zsign-src\bin\zsign` |
| 2 | **pymobiledevice3 装大 IPA 在 Windows 卡死** | 大包用爱思助手拖拽安装 |
| 3 | **TikTok 私有类名明文 → 反 hook SIGTRAP 闪退** | 类名 XOR 运行时解码 + noinline + volatile 防常量折叠（v1.4.142） |
| 4 | **dispatch_sync 主线程嵌套自锁 → watchdog 杀进程** | 外层 dispatch_sync 里别再 dispatch_sync（edit_profile/logout/register 修过 3 处） |
| 5 | **合成触摸对 TTKTabBarButton 无效**（target_actions 空） | 切 Tab 用 `setSelectedIndex` / 按 VC 类选，别用合成触摸 |
| 6 | **open_tab home 在非 feed 页假成功**（异步深链被忽略，命令却返回成功） | 真导航要先确认页面到达再报成功，别急返回 |
| 7 | **React 组件定义在组件函数体内 → 每次渲染重挂** | 组件移到模块顶层（v1.4.119 输入框丢字符血证） |
| 8 | **设备 secret 走 URL → 明文进日志** | 改走 X-Device-Secret header |
| 9 | **iOS 16.7 dyld3 不调用注入 dylib 的 `__attribute__((constructor))`** | 启动用 `+load` / 双层启动机制 |
| 10 | **VPS 构建目录不清理 → 残留旧文件掩盖改名问题** | 改文件后清 `/root/xnow-build/` 重编验证一次 |

---

## 9. 常用工具脚本（仓库根）

| 脚本 | 用途 |
|---|---|
| `build-vps-dylib-143c.py` | VPS 交叉编译 dylib |
| `.tmp-inject-143c.py` | 上传 dylib → vps-inject → 打包 IPA → 下载 |
| `.tmp-poll-netdiag.py` | ssh 查 server.log 拿设备执行结果（前端不回显时） |
| `collect-control-map.py` | ui_scan 采集控件基线地图 |
| `regression-check.py` | 发版前六条命令三态回归 |
| `fix-dylib.py` | dylib 修复 |
| `build-bh-ipa.py` | 本地打包（需原始包，本地无） |
| VPS 端 | `/opt/xnow-flow/vps-inject.py` 注入 + 产物 `/opt/xnow-flow/static/` |

---

## 10. 版本史要点（v1.4.90 → v1.4.143c）

| 版本 | 里程碑 |
|---|---|
| v1.4.108+ | 设备 secret 改走 header；设备 id Keychain 根治（重装不漂移） |
| v1.4.114~115 | 设备标识根治：激活/授权统一稳定 device_id + 硬件 UDID（IOPlatformUUID） |
| v1.4.119 | 攒批 4 项（国家/智能浏览崩溃/修改资料/关注失效）+ React 组件顶层化修复 |
| v1.4.123~125 | edit_profile 崩溃真根因 = dispatch_sync 嵌套自锁；修 3 处同类 |
| v1.4.127 | 攒批修 7 项假成功/卡死 + 发版门禁装机全量验证硬性落地 |
| v1.4.128~129 | open_tab 崩溃根治（全树遍历卡死 → 轻量深链兜底）；控件地图 |
| v1.4.130~133 | 触摸盲区根治：XNTouchSimulator IOHIDEvent 真实注入；设备 id Keychain 根治 |
| v1.4.134 | acc_click 验证证死 |
| v1.4.135 | **网络层点赞 `net_like`**（纯网络层第一步） |
| v1.4.136~140 | 网络探针系列：net_diag → net_sniff → net_classes → net_socket；zsign DER 修复 |
| v1.4.141~142 | **141 闪退根因实锤**（TikTok 私有类名明文 → SIGTRAP）+ XOR 防折叠修复；net_request 抓到自研栈请求明文 |
| v1.4.143c | **签名复刻第一测**：cookie_dump 命令 + net_like 支持 extra_headers 合并 X-Argus 签名头；**止损结论**：douyin-sign 抖音常量解不开 TikTok iOS 签名，现成库无 iOS 常量 |

**当前攻关方向**：验证 141 闪退修复（142 待装机验证）+ like/follow 回归根因（假成功导航链，非控件漂移）。

---

## 11. 文档索引

| 文档 | 内容 |
|---|---|
| `docs/TK云控系统-完整项目实施计划书.md` | 旧版完整规划（PPT 对照） |
| `docs/云控功能清单.md` | 功能清单 |
| `docs/control-map/` | 控件基线地图（8 页） |
| `docs/action-plan-*.md` | 网络层攻关行动方案 |
| `ISSUES.md` | 问题清单（发版门禁依据） |
| `*.md` 根目录审计报告 | DEV-REVIEW / SYSTEM-AUDIT / TEST-REPORT 等 |
| `CLAUDE.md` | 本项目规则（发版门禁/铁律） |

---

*本文由当前代码现状整理；有新改动请同步更新「版本史」与「已知问题」。*
