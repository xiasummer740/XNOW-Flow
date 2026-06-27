# XNOW-Flow 进度

## 2026-06-27 Xcode 15+ 链式 fixup 不兼容 iOS 16.7 — 全方案尝试失败

### 已修复的 Bug
- [x] `vps-inject.py`: `LC_LOAD_DYLIB = 0x8000001D` 应为 `0x0C`（导致爱思"未知的Mach格式"）
- [x] `vps-inject.py`: dylib_command struct 布局错误（name_offset=0 应为 24）
- [x] `vps-inject.py`: `__LINKEDIT` 检测用错命令号（0x2E 应为 LC_SEGMENT_64 + 看 segname）
- [x] `AccountManager.m`: `self.__currentAccount` 应为 `__currentAccount`（Xcode 15.4 编译错误）
- [x] `Makefile`: install_name 改为 `@executable_path/Frameworks/xnower.dylib`（和注入路径匹配）
- [x] CI Workflow: 使用 macos-14 runner + 编译后 Python 后处理

### 闪退根因定位
**问题**: iOS 16.7.15 (iPhone 8 Plus) dyld4 崩溃 `"bad lazy bind opcode 0x50"`
**根因**: Xcode 15+ 链接器默认生成链式 fixup（chained fixups），iOS 16.7 dyld4 处理不了重签后的链式 fixup 格式

### 尝试过的修复方案（全部失败）
1. ✅ 修正 LC_LOAD_DYLIB 注入命令 → 爱思签名通过，但运行时 dyld 崩
2. ❌ 剥离 fixup LOAD COMMANDS（不移除数据）→ 仍崩（dyld 从 __LINKEDIT 裸读数据）
3. ❌ 剥离 fixup LOAD COMMANDS + 填零 fixup 数据 → 仍崩（同样的错误）
4. ❌ 剥离 fixup 命令 + 填零数据 + 添加空 LC_DYLD_INFO_ONLY → 仍崩
5. ❌ 调整段偏移（delta=8）→ 爱思签名通过但运行时仍崩
6. ❌ 注入到 BHTikTok.dylib 而非主二进制 → 爱思"arch结构错误"（FAT 头未更新）
7. ❌ 修正 FAT 头 size/offset + 注入 BH dylib → 爱思签名通过，运行时仍崩

### 当前结论
**Mac 上 Xcode 15+ 编译的 dylib 在 iOS 16.7 上无论如何都无法工作。** 后处理（剥离 fixup/填零/加 INFO）无效。必需用 Xcode 14 或更早版本编译。

### 下一步方案（需新对话）
1. **用 macOS 编译** — 找台 Mac + Xcode 14，`make dylib` 直出兼容 dylib
2. **VPS 装 theos 交叉编译** — Linux 上装 theos + iOS SDK 编译 dylib（已装好 clang/git/make）
3. **换注入方式** — 不用 LC_LOAD_DYLIB，改 dlopen + hook（复杂）
4. **换设备** — iOS 17+ 可能处理链式 fixup 更好

### 环境
- Device: iPhone 10,2 (8 Plus) / iOS 16.7.15 (20H380)
- VPS: 192.129.210.52 / root / 0ISvaWdV88lLq871Re
- VPS 已装: clang 10, git, make, theos 克隆中
- 证书: Apple Distribution: alvaro reyes (2YH8B2Z9X9) 过期2027-06-17
- GH Actions: macos-14 (Xcode 15.4), 产物自动 artifact
- 爱思助手 v9
- CI: `ios-plugin/scripts/strip-chained-fixups.py` 编译后后处理
- IPA 基底: `TikTok_43.7.0_BH.ipa` (BH 1.9.3 插件版)
