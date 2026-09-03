# XNOW-Flow

> IPA 构建/注入工作流

## 说明

构建和注入 iOS IPA 的脚本集合，含 dylib 注入、证书替换、多版本构建。

## 关键脚本（2026-08-31 清理后现状）

- `build-vps-dylib-<版本>.py` — VPS clang-16 交叉编译 xnower.dylib（当前：`build-vps-dylib-143c.py`）
- `.tmp-inject-<版本>.py` — 上传 dylib → VPS vps-inject.py 注入 → 打包 IPA（VPS 无 43.7.0 原始包，以 static 最新已注入 IPA 连续注入）
- `.tmp-poll-netdiag.py` — ssh 查 server.log 拿设备执行结果（前端"执行结果"区不回显时用）
- `build-bh-ipa.py` — 本地打包（需 TikTok_43.7.0_BH.ipa 原始包，本地无）
- `fix-dylib.py` — dylib 修复
- VPS 端：`/opt/xnow-flow/vps-inject.py`（注入）+ 构建产物 `/opt/xnow-flow/static/`

## 注意

- 构建产物在 `build-artifacts-ci/`（各版本 dylib 子目录）
- dylib 编译走 VPS 交叉编译（clang-16 arm64-apple-ios16.5），不需要本地 Xcode 工具链
- **zsign 重签必须 `-z 9`**（2026-09-01 实测）：zsign 默认 zip_level=0 **不压缩**，重签后包从 374MB 膨胀到 685MB，iPhone 8 Plus (USB 2.0 + iOS 16) 装到 74% 卡死；`-z 9` 回到 ~391MB 正常安装。修复版 zsign 在 `C:\Users\Administrator\Downloads\zsign-src\bin\zsign`（WSL 跑 Linux ELF）
- **pymobiledevice3 apps install 装大 IPA（700MB+）在 Windows 卡死**（installd 无活动）——大包用爱思助手拖拽安装；爱思安装卡死时杀 i4Tools/i4Service/i4ToolsService 重启（设备 USB 不受影响）

## 🚦 发版门禁（攒批装机，不单点发版）

**状态机**：待修 → 已修待验 → 已备待发 → 已验证（真机/实测通过）

- **修复阶段不打包**：连续修问题，攒够 **≥3 个「已修待验」** 才编译打包
- **攒批清单**：已修待验的问题累积进 ISSUES.md 的「已备待发」段，攒够 3-5 项才触发构建
- **一次装机验全批**：打包一个 IPA，一次性装机验证批内全部问题 → 全过 → 标「已验证」→ 才算发版完成
- **装机=全量验证（2026-08-27 祥哥二次批评后硬性落地）**：装机后**不许只验当前 bug**——生成「装机验证清单」= ISSUES.md 全部「已修待验」+「待修」项 + 本次新修，**逐项下发命令实测**，每项记 真成功/假成功/崩溃，全部验完标状态才交付；验出的新问题并入下一批，**不中途单发**
- **发版前必跑回归清单（2026-08-28 祥哥批评「越做越差」后落地）**：改任何东西、编译任何版本前，先跑 `python regression-check.py all`（六条核心命令 open_tab/like/open_search/follow/go_home/backup，三态验收 ✅真成功/❌假成功/🚨崩溃）。任一 🚨 或 ❌ 核心项 → 不发版先修。防改 A 崩 B（v1.4.127 open_tab pop 自锁回归 = 血证）；验收关键字绑定 CommandEngine.m 返回格式，改返回要同步改脚本
- **控件基线地图（2026-08-28 落地，根治「锚点靠猜」）**：修任何控件问题前，先查 `docs/control-map/`（ui_scan 采集的 accId/label/坐标）。TikTok 更新后 `python collect-control-map.py <页面>` 重采对照 diff，锚点漂移一眼看出，不现场猜、不靠历史记忆
- **开工先盘点**：任何 bug 修复开始前，先 grep ISSUES.md「已修待验/待修」，把相关待验项规划进同一版
- **例外**：闪退 / 安全漏洞等紧急修复，祥哥特批可单发
- **构建产物**：`TikTok_XNOW_<version>.ipa` 上传 `/opt/xnow-flow/static/`，祥哥 i4Tools 装机
