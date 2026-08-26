# XNOW-Flow

> IPA 构建/注入工作流

## 说明

构建和注入 iOS IPA 的脚本集合，含 dylib 注入、证书替换、多版本构建。

## 关键脚本

- `build-final.py` — 最终构建
- `build-inject-*.py` — dylib 注入各版本
- `build-ipa-v*.py` — IPA 构建各版本
- `fix-dylib.py` — dylib 修复

## 注意

- 构建产物在 `build-artifacts/` 和 `build-artifacts-ci/`
- 需要 Xcode 工具链环境

## 🚦 发版门禁（攒批装机，不单点发版）

**状态机**：待修 → 已修待验 → 已备待发 → 已验证（真机/实测通过）

- **修复阶段不打包**：连续修问题，攒够 **≥3 个「已修待验」** 才编译打包
- **攒批清单**：已修待验的问题累积进 ISSUES.md 的「已备待发」段，攒够 3-5 项才触发构建
- **一次装机验全批**：打包一个 IPA，一次性装机验证批内全部问题 → 全过 → 标「已验证」→ 才算发版完成
- **例外**：闪退 / 安全漏洞等紧急修复，祥哥特批可单发
- **构建产物**：`TikTok_XNOW_<version>.ipa` 上传 `/opt/xnow-flow/static/`，祥哥 i4Tools 装机
