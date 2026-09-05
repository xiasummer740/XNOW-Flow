# XNOW-Flow 进度

## 2026-09-05 ⏳ v1.4.149 已打包待装机（A4 账号池同步 + open_tab 非 home 假成功修复）

- **A4（Task #38）已修**：backup_account 成功后主动上报 status(current_account)——XNOWER.h 声明 + XNOWER.m `reportBackedUpAccount` 实现（AccountManager.currentAccount 优先、AccountPool.activeAccount 兜底映射）→ `XNURLProtocol sendMessage` 带 X-Device-Secret 直连 POST /ws/{device_id}（poll 同款可达通道）+ CommandEngine backup 成功分支触发。根因=148 起 HTTP poll 模式 heartbeat/wsClientDidConnect 从不触发（startHeartbeat 只挂 wsClientDidConnect L480）→ 账号从不自动上报。
- **open_tab 非 home 假成功盲区（Task #39）已修**：CommandEngine.m 4 处——handler 读 `diag.reached`=NO 诚实返回 status=failed（不再无条件假 success）；acc_id_tap/坐标兜底非 home 标 reached=NO（不设假 currentPage）；class_no_match dump tab bar 实际 VC 类名（realTabVCs）取证下版直切 profile。home 路径不动。
- **已提交** af5eca1（5 文件，无 Co-Authored-By）+ VPS 编译 xnower-149.dylib 866504 bytes + 注入 `TikTok_XNOW_v1.4.149_BH.ipa` 374.3MB（static + 本地，VPS 残留已清）。
- **编译前回归**：open_tab home/go_home/like/open_search/backup 全健康；follow ❌ = 基线已知搁置（2026-09-04 祥哥拍板），非本批引入。
- **装机验证清单**：①backup_account → 后端 `/api/biz/v2/accounts/` count=1（A4）②open_tab profile → 诚实 status=failed + server.log 见 realTabVCs 真实 VC 类名（open_tab）③回归六命令复查。
- 待祥哥 i4Tools 装机 TikTok_XNOW_v1.4.149_BH.ipa 后下发验证。

## 2026-06-27 ✅ 首次成功！TikTok 启动通过

### 最终成功方案（v19）
- **注入目标**: `BHTikTok.dylib`（FAT 二进制），而非主二进制
- **dylib 编译**: GitHub Actions CI on macos-14 (Xcode 15.0.1) + `-Wl,-no_fixup_chains`
- **关键修复**:
  1. 注入到 `BHTikTok.dylib` 而非主二进制 — 绕过主二进制私有命令体系（0x80000018）
  2. `-Wl,-no_fixup_chains` 编译 — 生成 LC_DYLD_INFO 旧式绑定信息
  3. 正确更新段偏移（fileoff/section/symtab/codesign）+72
  4. FAT 二进制重建时保持 16384 对齐（否则爱思报"arch结构错误"）
  5. 不能用 VPS lld 链接器（Mach-O 输出 iOS 16.7 dyld 不认）
- **产物**: `TikTok_XNOW_v19.ipa`
- **启动状态**: TikTok 成功打开

### 失败经验总结

| 轮次 | 问题 | 根因 | 教训 |
|------|------|------|------|
| 1-3 | strip 链式fixup后闪退 | LC_DYLD_INFO 全零→无绑定信息 | strip必须同时填充绑定数据 |
| 4-6 | 爱思"未知的Mach格式" | 注入后未更新段偏移 | 插入命令必须更新所有偏移字段 |
| 7-8 | 闪退 | VPS lld 的 Mach-O iOS16 不认 | Linux 交叉编译不可靠 |
| 9 | 闪退 | 主二进制用标准0x0C和私有0x80000018冲突 | 主二进制必须用私有命令 |
| **10** | ✅ **成功** | **改BHTikTok.dylib（FAT对齐）+ macOS CI dylib** | **绕过主二进制，dylib必须macOS原生编译** |

### 关键结论
1. **不能改主二进制** — TikTok 用 0x80000018（私有命令）加载所有 BH dylib，加标准 0x0C 会导致冲突
2. **必须用 macOS Apple ld 链接** — lld/ld64.lld 的 Mach-O 输出 iOS 16.7 dyld 不认
3. **Xcode 15 + `-no_fixup_chains` 可以工作** — 旧结论"Xcode 15 无论如何不能工作"是错的，正确的 flag 是 `-Wl,-no_fixup_chains` 而非 `-no_chained_fixups`
4. **FAT 二进制修改必须保持对齐** — 多架构 FAT 切片之间的填充必须正确对齐到 align 字段

### 工具链
- `build-inject-bhtiktok.py` — 注入到 BHTikTok.dylib（含正确 FAT 对齐处理）
- `build-inject-fixed.py` — 注入到主二进制（含完整偏移更新，仅作参考）
- `build-minimal-vps.py` — VPS 交叉编译（仅作参考，lld 输出不兼容）
- CI: GitHub Actions macos-14 / Xcode 15.0.1
- 爱思助手 v9 签名
- dylib 编译 flag: `make dylib LDFLAGS="-Wl,-no_fixup_chains"`

### 当前状态（2026-06-28）

**核心结论：dylib 从未被执行过**

经过 16 个版本迭代，所有代码（dispatch_after / CFRunLoopPerformBlock / pthread_create / +load）均未产生任何可见输出。红色诊断条从未出现，浮窗从未显示。

| 版本 | 方案 | 结果 |
|------|------|------|
| v19 | 注入 BHTikTok.dylib LC_LOAD_DYLIB | TikTok 能打开，代码不执行 |
| v20-v21 | + viewDidAppear/sendEvent 钩子 | 同上 |
| v22 | 注入主二进制 0x80000018 | 闪退（偏移损坏） |
| v23 | BHTikTok + 角标/sendEvent | 闪退（代码组合问题） |
| v24 | 纯回退 v19 原始代码 | 能打开 ✅ |
| v25 | +1 秒重试 | 能打开，浮窗不显示 |
| v26-v33 | 注入 libswiftCore.dylib（0x0C 强依赖） | 能打开，代码不执行 |
| v34 | 替换 libFLEX.dylib | 闪退（FLEXing 符号缺失） |
| v35 | BHTikTok + dispatch_after 全局队列 | 能打开，代码不执行 |
| v36 | BHTikTok + pthread_create | 能打开，代码不执行 |
| v37 🆕 | BHTikTok + **ObjC +load 替代构造函数** | 待测试 |

### 关键发现

1. **dyld3 在 iOS 16.7 可能跳过 dylib 的 __mod_init_func（构造函数段）**
   - dispatch_after / CFRunLoopPerformBlock / pthread_create 在 dyld 阶段都能被正确调度
   - 但 block 内的代码从未执行 → start() 从未被调用
   - 说明构造函数（__attribute__((constructor))）根本未被 dyld 调用
   - v37 换用 +load（通过 libobjc add_image 回调，不走构造函数）→ **待验证**

2. **注入 BHTikTok.dylib 能过 i4 重签**（v19 已验证）
   - 注入主二进制或系统库可能被 i4 的签章工具破坏偏移
   - v22（主二进制 0x80000018）→ 闪退
   - v26-v33（libswiftCore.dylib）→ 能打开但代码不执行（可能签章修复了偏移但构造函数跳过了）

3. **替换 dylib 文件不可行**（v34）
   - FLEXing.dylib 依赖 libFLEX.dylib 的符号 → 替换后符号缺失闪退

4. **框架兼容性**
   - WebSocket 连接：ws://192.129.210.52:8000（VPS）
   - 设备：iPhone 8 Plus / iOS 16.7.15
   - CI：GitHub Actions macos-14 / Xcode 15.0.1 / `-Wl,-no_fixup_chains`

### 待验证（v37）
- [ ] ObjC +load 能否被 libobjc 调用（即使 dyld 跳过构造函数）
- [ ] 如果 +load 也不工作 → 需要考虑 dylib 的代码签名/验证问题

### 待开发
- [ ] dylib 功能：浮窗、WebSocket、命令引擎
- [ ] 后端对接验证

### 环境
- Device: iPhone 10,2 (8 Plus) / iOS 16.7.15 (20H380)
- VPS: 192.129.210.52 / root / XNW_VPS_PASSWORD_FROM_ENV
- 证书: Apple Distribution: alvaro reyes (2YH8B2Z9X9) 过期2027-06-17
- GH Actions: macos-14 (Xcode 15.0.1), 产物自动 artifact
- IPA 基底: `TikTok_43.7.0_BH.ipa` (BH 1.9.3 插件版)
- 成功 IPA: `TikTok_XNOW_v19.ipa`

## 2026-09-05 ✅ 148 全量装机验证（16 项清单跑完，任务 #37 关闭）

- **结果（后台/远端实测，逐项记录见 ISSUES.md「✅ 下批装机验证结果」L493+）**：**A 组 3 过 1 新 bug**——A1 secret header ✅（poll URL 无明文）/ A2 硬件 UDID 自动激活 ✅（auto-activate-iphone_A8DE7E93 无卡密框）/ A3 备份资料+国家 ✅（country:gb + 90+ profile_keys）/ **A4 B41 账号池同步 ❌ 新 bug**（设备 HTTP poll 模式从不 POST status → backup 后账号不上报 `{"count":0}`）。**B 组代码层全过**（B7-B13）。**C 组**：C14 save_video 假成功暴露、C16 open_search ✅ 真成功 / search_keyword ❌ 触摸墙、C15 修改资料 blocked。
- **新待修 3 项已登记 ISSUES（下一批候选）**：A4 账号池同步（修复方向=HTTP poll 周期 POST status(current_account) / backup 成功后主动 POST）、C14 save_video 假成功（-void handler 默认 OK + lastFeedVideo 抓不到→从未真下载）、open_tab 非 home tab 假成功盲区（无落位验证，阻塞账号管理/切号/改资料真机验收）。
- **ISSUES 行状态已翻**：→已验证 16/43/50/55/56/57/71；→部分验证 29/42/53/65/67；→待修 54（C14 假成功）+ A4/open_tab 新登记。B41(62)/账号按钮(64)/修改资料(69) 保持已修待验 + 备注阻塞。
- 设备收尾回 feed、无崩溃、持续 poll 在线。commit + handover 2026-09-05。

## 2026-09-04 follow 搁置 + 全量验证计划

- **v1.4.148 装机验证（祥哥装，后台测）**：follow 方向 D（深链进 profile 点 UIControl）**证伪**——`after: '<profile未到达>'`。
- **根因定位 = 43.7.0 三重反自动化墙**（均有证据，见 ISSUES.md 148 段）：①触摸墙：feed 右侧互动控件 Swift 手势验真实触摸，sendActions/gr_fire/KVC 全拒；HID 真实注入沙盒拿不到 ContextID（ctx_probe ctx=0 servicesCount=1）②深链墙：snssdk1233://user/<用户名>/<数字uid> 全不导航 ③网络墙：net_like 从没成功（feed SwiftNIO 抓不到 + X-Gorgon 签名未解）。
- **祥哥拍板：搁置 follow**（方向 E 直调 VC 待特批才投），下批对**已装 148 直接跑全量验证清单**清 16 项已修待验（ISSUES「下批装机验证清单」A账号1-6/B面板7-13/C触摸墙14-16），不再被 follow 卡发版。
- 已提交推送 b3f13e9（ISSUES 决策+清单）+ handover 2026-09-04-v1.4.148-follow-blocked.md。
- **待办**：跑下批验证清单（任务 #37），验过项 ISSUES 翻「已验证」。

## 2026-08-26 发版门禁规则落地

- 攒批策略之前只写在 ISSUES.md 底部 + 全局发版门禁，本仓库 CLAUDE.md 没有 → 每修一个就发一版（v1.4.88→v1.4.123），祥哥反复装机。
- 已在本仓库 CLAUDE.md 加「🚦 发版门禁」章节：状态机 待修→已修待验→已备待发→已验证；攒够 ≥3 项「已修待验」才编译打包；一次装机验全批；闪退/安全紧急单发需祥哥特批。
- ISSUES.md 状态机补「已备待发」态 + 攒批门禁说明。
- 后续发版前先数「已备待发」，不够 3 项不打包。

## 2026-08-31 清理 + 纯网络层 Step 0 探针

- **清理**：删除 47 个历史构建/临时脚本（build-vps-dylib-89~137、build-inject/build-ipa、40+ 个 .tmp-*.py 调试残留），当前工作流只留 build-vps-dylib-138.py + .tmp-inject-138.py + .tmp-poll-netdiag.py；CLAUDE.md 关键脚本段已同步。
- **v1.4.138 决定性网络探针（待装机）**：registered 读取修复（NSHashTable）、global_asked 全局计数、session swizzle 扩 dataTaskWithURL/uploadTask、net_sniff 时间盒命令。装机后下发 net_sniff 10 + net_diag 判路线 C/B/A（判定表 docs/action-plan-pure-network-layer.md:42-48）。
- **交接**：handover 2026-08-31-v1.4.138-net-layer-step0.md + TODO 已更新，commit c7bcf7b。
