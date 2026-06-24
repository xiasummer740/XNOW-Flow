# XNOW-Flow 进度

## 2026-06-24 AltServer 环境搭建 + TikTok 侧载成功

### 已完成
- [x] AltServer 0xc000007b 修复 → 安装 AltInstaller.msi v1.7.4 启动成功
- [x] Apple Application Support (x86/x64) + iCloud v7.21.0.23 + Bonjour 全部安装
- [x] 淘宝 p12 企业证书导入爱思助手，签名成功
- [x] TikTok_42.2.0_BH.ipa 签名并安装到 iPhone (16.7.15)，运行正常

### 遗留问题
- [ ] **TikTok_XNOW.ipa 闪退** — 证书签名有效，BH版能打开，XNOW版信任后点开闪退
  - 推测：XNOW 插件注入的 dylib 与当前 TikTok 版本或 iOS 16.7.15 不兼容
  - 需排查：检查 XNOW 插件依赖的库版本 / hook 的符号是否在 BH 版中存在
- [ ] XNOW 插件本身可能需要重新编译或适配

### 关键决策
- 侧载方案：放弃 AltStore/Sideloadly/爱思助手 Apple ID 签名（2025年Apple认证接口已变更，全部报认证错误）
- 改用：淘宝 p12 企业证书 + 爱思助手签名，一次搞定

### 环境
- Windows Server 2025 (26100) / E:\software\AltServer.exe 运行中
- E:\software\i4Tools8\i4Tools.exe 可用
- p12 证书：Apple Distribution: alvaro reyes (2YH8B2Z9X9)，过期 2027-06-17
