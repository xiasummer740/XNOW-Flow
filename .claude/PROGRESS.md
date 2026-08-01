# XNOW-Flow 进度

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
