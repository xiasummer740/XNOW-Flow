# v1.4.88 全自动真机验证报告

> 日期：2026-08-15 ｜ 方式：全程远程自动验证（后端 API → 设备 WS 命令通道），祥哥零操作
> 证据来源：`/opt/xnow-flow/server.log`（polled/result/touch_diag/state_diag/STEP）+ 后端 DB（tasks/collected_data/accounts）
> 时间：文中时间 = BST（设备日志），DB 时间为 UTC（差 +1h）

## 一、验证结论速览

| # | 能力 | 结论 | 证据 |
|---|------|------|------|
| 1 | 命令通道（dispatch→poll→execute→result） | ✅ 通 | server.log 多命令往返 |
| 2 | 点赞 like | ✅ **真实成功** | state_diag `acc_label='Video liked'` |
| 3 | 打开搜索 open_search | ✅ 真实成功 | 09:13:18 result OK |
| 4 | 滚动 scroll_down/up | ✅ 成功 | 09:09:46~09:09:57 result OK |
| 5 | 截图 / UI 扫描 | ✅ 成功 | result OK + ui_scan 元素返回 |
| 6 | 页面检测强化（首页 feed 直播卡片不误判直播间） | ✅ 正确 | 实际在 feed 时返回 home 菜单 |
| 7 | 首页菜单重构（移除采集三件套） | ✅ 配置正确 | 离线复刻 + 真实 feed ui_scan 预测 = home 菜单无采集项 |
| 8 | 我的主页/别人主页区分 | ⚠️ 代码已实现，真机不可达 | 导航坏（见 P0-2） |
| 9 | 别人主页菜单（自动关注/采集粉丝/采集视频） | ⚠️ 真机不可达 | 导航坏 |
| 10 | 直播间菜单（采集点赞等） | ⚠️ 真机不可达 | 导航坏 |
| 11 | 粉丝列表菜单（自动关注） | ⚠️ 真机不可达 | 导航坏 |
| 12 | 采集粉丝/视频/点赞/评论数据 | ❌ collected_data=0、accounts=0 | DB 实查 |
| 13 | 崩溃/死锁/看门狗 | ✅ 无崩溃 | 本次会话全程无 kill |
| 14 | 面板存在 + 设备激活 | ✅ | license poll 200；浮窗代码链路在 |
| 15 | 后台任务状态显示 | ❌ 全部误报失败 | 见 P1-2 |

## 二、发现的问题（按严重度，产品视角）

### 🔴 P0-1 搜索关键词卡死，单条命令拖垮整台设备（新发现·已实锤）
- **现象**：`search_keyword` 09:13:52 被设备拉取后 **90 秒无结果**；此后 ui_scan×3、check_health 全部积压（Connection_manager queued total 3→4）；设备心跳停止，**09:15:59 被 offline-sweep 标记离线**。
- **证据**：
  - `09:13:52 polled command: search_keyword` → 之后 server.log **再无任何该命令 result**；
  - `09:15:09 Command queued: ui_scan (total: 3)`、`09:15:54 queued: check_health (total: 4)` —— 设备不再拉取；
  - `09:15:59 [offline-sweep] marked 1 devices offline`；
  - DB task#86 `search_keyword` 08:13:47 建单，实际从未在设备端完成。
- **根因**：`_performSearchKeyword:` 无超时；CommandEngine 串行 `_execQueue` 无命令级超时 → 一条卡死命令阻塞整条通道+心跳 → WS 超时掉线。
- **影响（产品）**：任何用户发起搜索 → 整台设备变"僵尸"，后台显示离线，所有任务瘫痪。
- **建议**：搜索命令加 `dispatch_after` 兜底返回；`_execQueue` 支持命令级超时/看门狗。

### 🔴 P0-2 远程导航全部失效：主页/直播间/粉丝列表都去不了（已实锤）
- **① open_tab（切 profile tab）假成功**：gesture `_setState:Recognized` 注入返回 success，但 touch_diag 显示 `isSelected` 仍是 **False**，tab 实际没切。TTKTabBarButton 的 UITapGestureRecognizer `target_actions=[]`，注入绕过了真实触摸投递。
- **② open_profile（打开个人主页）三连坏**：
  - 深链 `snssdk1233://user/xxx` 无跳转（实测仍停在 feed）；
  - 头像控件类名漂移：现在是 `AWEStoryAvatarButton`（无 `acc_id="avatar"`），代码按旧类 `AWEPlayInteractionUserAvatarView` 找不到；
  - 固定坐标兜底按 `(0.08w, 0.82h)=(34,764)` 点**左下角**，而头像在**右上 (~384,291)**。
- **影响（产品）**：**所有需要"先导航到页面"的功能全部不可达** —— 采集粉丝/采集视频/采集点赞、自动关注、账号管理、直播间采集。这是 `collected_data=0 / accounts=0` 的直接根因。
- **建议**：open_profile 重写 UI 找头像逻辑（可见性+位置+多候选类名）；open_tab 改真实触摸投递。

### 🟠 P1-1 评论区按钮按到屏幕外（AWEMaskWindow）（已实锤）
- **证据**：comment 命令 → touch_diag 显示命中 `(x,1170) AWEMaskWindow`（屏幕外 y=1170），而非可见评论按钮（屏内 y≈434）。
- **根因**：`_openCommentPanel` 用 `_findViewWithAccessibilityIdentifier:`（**不筛可见性**）命中了下一视频预取的无障碍按钮。
- **对比（铁证）**：like 用 `_findVisibleViewWithAccId`（**筛可见性**）就真成功（state_diag `Video liked`）—— 证明不是点击机制坏，是"找元素没过滤可见"。
- **影响**：自动评论点赞、采集评论全部失效。
- **建议**：评论相关查找全部改可见性过滤。

### 🟠 P1-2 后台任务状态全部误报"失败/无有效目标单元"（已实锤）
- **证据**：DB tasks 表**每一条**远程指令任务 `status='failed', error='无有效目标单元'` —— **包括实际成功的** like(08:12:28) / open_search(08:13:13) / scroll_down(08:09:46~57)。设备端 server.log 明明有 result OK。
- **根因**：task_engine.py:116-124 —— 远程指令（config={}, 无 targets）被 `total<=0 or not targets` 分支直接判 failed。
- **影响（产品）**：云控后台所有指令显示"失败"，用户以为全坏了，实际多数成功。**后台数据失真=不可信**。
- **建议**：远程指令按设备返回结果标记；无 target 不应直接判 failed。

### 🟡 P2-1 采集数据为 0（后果，非独立 bug）
- collected_data=0、accounts=0。这是 P0-2 导航坏的直接后果；修好导航后应自愈，不需要单独处理。

### 🟡 P2-2 IPA 版本显示 "dev"
- v1.4.88 用 build-bh-simple.py 构建时未传版本号 → 默认 `dev`。浮窗版本可能显示 dev，让祥哥误以为没升级。下次构建传 `v1.4.88`。

## 三、已验证通过的能力（亮点）
1. **命令通道端到端通** —— dispatch→poll→execute→result 全链路 OK，WS 稳定性正常（无崩溃）。
2. **点赞真实成功** —— state_diag `Video liked` 铁证，可见性查找模式正确。
3. **打开搜索成功** —— 固定坐标点可见搜索图标有效。
4. **滚动成功** —— scroll_down 连续 3 次 OK。
5. **页面检测强化生效** —— 首页 feed 直播预览卡片**不再误判直播间**（返回 home 菜单），锚点改造成功。
6. **首页菜单重构正确** —— 首页菜单已移除采集三件套，只剩绑定/账号/下载/设置/清理/关服/养号。
7. **v1.4.86/87 崩溃修复验证** —— 本次会话全程无崩溃/死锁/看门狗 kill。
8. **面板存在 + 设备激活** —— license poll 200，浮窗独立窗口链路代码在。

## 四、产品经理综合分析
- **一句话结论**：v1.4.88 的菜单重构方向**完全正确**（首页去掉采集三件套、区分我的/别人主页、直播间加采集点赞），但当前版本在真机上"采集/关注类功能实际不可用"，且有一个能把整台设备搞离线的严重卡死 bug。
- **阻塞链**：`search_keyword 卡死(全局僵尸)` + `导航全坏(采集/关注不可达)` + `任务状态误报(后台失真)`。三者叠加，产品当前**不可对外使用**。
- **修复优先级**：
  1. P0-1 搜索超时保护（防僵尸）→ 2. P0-2 导航重写（解锁全部采集/关注）→ 3. P1-1 可见性查找（解锁评论类）→ 4. P1-2 任务状态（后台可信）。
- **预期收益**：修完这 4 个，采集粉丝/视频/点赞、自动关注、评论类从"理论可用"变"真机可用"，后台状态真实可信。
- **当前设备状态**：手机已离线（09:15:59），后续验证需重新打开 TikTok 恢复连接；真机无法到达的页面菜单验证（我的/别人主页、直播间、粉丝列表）已由**离线复刻**覆盖配置正确性，真机侧待导航修复后复验。

## 五、遗留 / 需祥哥拍板
- 是否授权按上述优先级修 P0/P1 共 4 个 bug（导航重写 + 搜索超时 + 可见性查找 + 任务状态）？修完重装 IPA 再全自动复验。
