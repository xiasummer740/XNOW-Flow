# 2026-09-01 zsign DER 修复 + 装机存活验证（任务 #7/#8 收官）

## 做了什么
1. **net_socket 探针（#7）**：设备激活 → 连 WS → 执行网络层抓包，抓到 4 个 TLS 连接真实数据（Akamai CDN + api16-normal-useast5.tiktokv.us + v16m.tiktokcdn-us.com），TLS 明文可见。
2. **zsign DER 修复（#8）**：zsign 把 DER 编码 RSA 签名（264 字节）塞进应放裸 RSA 签名（256 字节）的字段 → iOS trustd 报 `RSA sign - input buffer bad size (264 bytes)` → 启动 SIGTRAP 秒退。
   - 修复：改用标准 OpenSSL `CMS_sign` + `CMS_add1_signer(EVP_sha256)` + `i2d_CMS_bio`（本地源码 `C:\Users\Administrator\Downloads\zsign-src\src\openssl.cpp`），产出 CMS SignatureValue=256 字节。
   - 验证：`extract_cms.py` 解析 SuperBlob 确认 SignatureValue=256。
   - **装机存活确认**：dvt launch → 25 秒+ 进程活着 → TikTok feed 正常显示 → `device_online: true` → status 命令回复 `OK: status`。**DER 修复成立，zsign 签名版第一次存活。**

## 🔴 关键坑（必记）
- **zsign 重签默认 `zip_level=0`（不压缩）** → 685MB 大包（MusicallyCore 521MB 原样塞入）→ iPhone 8 Plus (USB 2.0 + iOS 16) 装到 74% 卡死。**必须加 `-z 9`**，包回到 391MB。
- **pymobiledevice3 apps install 装大 IPA（700MB+）在 Windows 上卡死**（两次，installd 无活动）。大包用爱思助手拖拽安装。
- 爱思助手安装卡死时 UI 取消无效 → 杀 i4Tools/i4Service/i4ToolsService 进程重启爱思（设备 USB 不受影响）。

## 最终可用产物
`F:\summer\vs-code\XNOW-Flow\TikTok_XNOW_v1.4.140_BH_xn_z9.ipa`（391MB，zsign -z 9 重签，CMS 256 字节）

## 决策副作用
- 685MB 的中间产物（_xn.ipa / _der / _rs / _rs2）占 ~2.7GB 磁盘，可清理。
- 装机路径依赖爱思助手（祥哥拖拽），pymobiledevice3 装大包不可用。

## 下一步
- 大包坑已沉淀到 CLAUDE.md（zsign 必须 -z 9）。
- 设备当前运行 v1.4.140 zsign 修复版，可继续下发 net_socket 等命令做网络层深挖。
