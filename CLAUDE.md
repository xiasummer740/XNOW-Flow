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
