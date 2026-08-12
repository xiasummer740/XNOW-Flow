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

### ✅ 2026-08-10 夜间真机验证（v1.4.76）

- **激活通过**：浮窗点开不用再输卡密（卡 SLUTRRL2RLNQGVXV 已重绑硬件UDID 9ED6D3B0）
- **切首页 go_home 成功**：touch_diag 命中 TTKTabBarButton(41,712)（与知识库 a11y_vo_home 一致），state_diag acc_label='Home'，result OK 9秒
- **关注 follow 待验**：已下发2次入队，但 go_home 成功后约40秒设备停止轮询被判定离线（15:27:24 UTC 后无心跳），疑似锁屏/App后台/浮窗收起

### 🟢 2026-08-11 全面审查 + 安全修复第一批（已上线 VPS）

**审查结论**：3 专项 Agent + 实机验证，后端 6 高危/设备端 3 高危/构建发版 4/10。详见 ISSUES.md。

### 🟢 2026-08-11 浮窗 UI 重新设计（苹果 HIG 风格预览中）

- 5 屏高保真 HTML 预览（收起态/主菜单/激活/绑定/独立日志小窗）+ 3 参考图对照，部署 `http://192.129.210.52:8000/fuweng-preview.html`
- 版本号功能：Config.plist 加 XNOWER_BuildVersion，build 脚本写入，浮窗标题显示 v1.4.76（代码完成，待装机验证）
- **PPT 分析发现关键需求**：千问识图确认「不同 TikTok 页面浮窗菜单不同」（feed/评论/个人主页/直播间/私信菜单各不同），需实现**页面感知菜单**

### 🟢 2026-08-11 浮窗页面感知菜单 + 翻译/口令（代码完成，待装机验证）

- **页面检测**：CommandEngine 新增 `detectCurrentPage`（live/comment/inbox/profile/home/other 6类，基于类名+控件特征）
- **动态菜单**：XNFloatingPanel `_buildPageMenu` 按页面渲染不同菜单（feed完整4组/评论互动/关注粉丝/直播采集/私信翻译）
- **翻译**：后端新增 `/api/biz/v2/translate/`（DASHSCOPE 千问），设备端 toggle_translate 通知+设置翻译语言子菜单
- **口令**：复用 reply_templates 关键词自动回复（口令=匹配规则）
- **直播间采集**：collect_live/start_live_collect 入口（复用 collect_live_users）
- 祥哥"你看着办"决策已记 autonomy-log.md
- **部署修复**：proxy 模块(proxy_node模型/routers/schemas)生产从未部署过，补齐 + proxy_nodes.py 兼容 Python3.8(Optional替代 dict|None)，翻译端点已上线真机验证通过
- **翻译端点已生产验证**：POST /api/biz/v2/translate/ "Hello, how are you today?"→"你好，今天过得怎么样？"（千问 qwen）
- **页面感知菜单代码完成**：detectCurrentPage(6类页面) + _buildPageMenu(5种菜单) + 翻译/口令/直播采集，待构建IPA装机验证

### 🟢 2026-08-12 字段级对比 + 中文化 + 全量功能对比

- **字段级对比完成**：采集数据缺头像URL/年龄/关注数（已修复），公共库缺年龄/关注数（已修复），设备缺添加人/锁定列（已补）
- **字段中文化**：前端 5 页补列（采集数据加头像/性别/国家/粉丝/关注/年龄，公共库加关注/年龄+年龄筛选，设备加锁定，账号修 follow_count bug）
- **后端补全**：public-users 支持 min_age/max_age 服务端筛选，DeviceBinding 加 added_by
- **全量对比页上线**：`http://192.129.210.52:8000/full-compare.html`（浮窗8✅2⚠️ / 后台8✅7⚠️9❌）

### 🟢 2026-08-12 打通后台8个缺失模块（已上线）

- **统一素材库页**（MaterialLibrary）：头像/昵称/签名/广告链接/网站链接 5分类切换 + 分组 + 批量导入
- **视频管理页**（VideoManagement）：发布记录+新建+立即发布
- **广告管理**（AdvertManagement）：后端 adverts 模型+接口+页面
- **回关自动私信**：设备端关注成功后取话术自动私信（fetchReplyTemplate + follow钩子）
- 素材类别区分：link_ad(广告)/link_site(网站)
- 全部已部署 VPS 验证（前端侧边栏3新菜单 + 素材库5分类标签 + 广告API）

### 🟢 2026-08-12 改资料功能补全（头像+一次性全改）

- 批量改资料支持**头像**：edit_avatar 从头像素材库抽图下发
- 设备端 edit_profile 支持 avatar 参数 + `_applyAvatarToProfile`（下载头像→存相册→选图）
- 前端批量改资料弹窗加"修改头像"勾选
- **完整能力**：针对某账号一次性改「头像+昵称+签名+广告链接+网站链接」全部资料（跨设备多账号也可批量）

**第一批已修复并部署（4项，全测过）**
- SECRET_KEY 启动守卫（config.py，无密钥拒启）
- 上传限 10MB + 禁 SVG（media.py）
- 任务/定时任务跨租户下发校验（tasks.py/timed_tasks.py）
- 设备鉴权收紧（ws.py：UUID 校验+恒定时间+关迁移期放行）

**遗留（第二批，需装机攒批）**：TLS 明文、secret 走 URL、batch_login 凭证明文、设备端掉线根因（poll 无重连）

### 🔴 待办/待验证（新对话优先）

1. **v1.4.76 follow 验证 + 设备掉线根因修复**（最高优先）：
   - 设备端 poll 静默失败无重连是昨晚掉线根因 → 需改设备端 + 重新构建 IPA
   - 装机新版后 follow 已排队会自动执行，state_diag 应显示 "Following X"
2. **设备端另外 2 个雷**：共享 session 被 invalidate、授权网络错误误判未激活
3. **第二批安全**：TLS + secret 改 header + batch_login 限权（需设备端改造）
4. **v1.4.76 硬件UDID确认**：IOPlatformUUID 是否拿到
5. **其他设备命令真机验证**：发视频选片/like_comment/open_live/follow_user/comment_video
6. **积攒批验证**：不再单点发版，攒 3-5 功能一次装机测

### 版本基线
- 设备 v1.4.76（最新，重装后标识 9ED6D3B0-617F-4DFB-8D71-0A730124D0F5）
- 激活卡 SLUTRRL2RLNQGVXV（已重绑新设备）
- 后端 v1.3.0（FastAPI + SQLite，VPS 192.129.210.52）
- 前端 React（login/）
