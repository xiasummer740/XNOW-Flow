# XNOW-Flow 进度

> 更新：2026-08-10 · 维护：Claude + 祥哥

## 当前主线：PPT 全功能开发（云控讲解.pptx）

**计划文档**：`PLAN-2026-08-08-PPT全功能对账与开发计划.md`

### ✅ 已完成

**第一批（后端，已验证）**
- 公共用户库完整版（VPS 8项验证 + 真实 qwen-vl 打标）
- 统一任务引擎（VPS 10项验证）
- set_country 环境伪装（真机验证通过，出口IP=美国）

**第二批（设备端命令，构建成功）**
- 发视频选片 / like_comment / open_live / follow_user / comment_video / 浮窗复制机器码

**切首页 + 互动养号**
- 切首页：`_setState:Recognized` 注入 tab 手势（v1.4.62 解决）
- 互动养号不崩：浏览稳定期互动 + 安全 accId/label+sendActions + 屏幕内过滤 + 深度30
- 点赞验证成功：state_diag "Video liked"（真红心）

**TikTok 原生代码信息库**
- `tiktok原生代码信息/`：feed(103)/inbox(75)/profile(75)/search(29) 控件全量 + 元素结构树
- 深度分析：完整视图层 11-27 层 → 查找深度统一 30

### 🔴 待办/待验证（新对话优先）

1. **v1.4.76 装机验证**（最高优先）：
   - 硬件 UDID（IOPlatformUUID）能否拿到 → 卡绑不变标识，重装不失效
   - 浮窗输卡密激活（activate 已改 deviceUID 统一）
2. **关注最终验证**：深度30后 follow 命中 FollowPromptView，state_diag "Following X"
3. **其他设备命令真机验证**：发视频选片/like_comment/open_live/follow_user/comment_video
4. **积攒批验证**：不再单点发版，攒 3-5 功能一次装机测

### 版本基线
- 设备 v1.4.76（最新，重装后标识 9ED6D3B0-617F-4DFB-8D71-0A730124D0F5）
- 激活卡 SLUTRRL2RLNQGVXV（已重绑新设备）
- 后端 v1.3.0（FastAPI + SQLite，VPS 192.129.210.52）
- 前端 React（login/）
