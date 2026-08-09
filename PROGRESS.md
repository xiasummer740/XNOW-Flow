# XNOW-Flow 进度

> 更新：2026-08-08 · 维护：Claude + 祥哥

## 当前主线：PPT 全功能开发（云控讲解.pptx）

**计划文档**：`PLAN-2026-08-08-PPT全功能对账与开发计划.md`（功能树/三层对账/四批执行顺序/决策/验收）

### 已完成
- ✅ **第一批第1项：公共用户库完整版**（已上线 VPS）
  - 后端 5 端点 + public_users 表 + qwen-vl AI头像打标（真实调用验证通过）
  - 前端 PublicLibrary.tsx（后台「内容」→公共用户库）
  - VPS `.env` 已配置 DASHSCOPE_API_KEY
  - 验证报告：计划文档第十节
- ✅ **第一批第2项：统一任务引擎基础模型**（已上线 VPS，commit c62d34a）
  - Task 模型加引擎字段（config/total/done/fail_count/last_log/error/started_at/next_dispatch_at）
  - task_engine.py 后台线程：running 任务按随机间隔逐单元下发，风控钳制（点赞≤300/关注≤200）
  - 下发 payload `{type:command, action, params}`，写 TaskExecution 审计
  - tasks 路由：创建(带config) + start(数据组target_group解析) + stop/pause/resume + `GET /tasks/status/running/`
  - 验证：风控钳制/完成闭环/停止/数据组解析/进度+last_log 全过
- ✅ **第一批第3项：设备端环境伪装 set_country/get_country**（祥哥方向调整后核心，commit 8acfbb0，v1.4.53 构建成功待装机）
  - CountryEnv：30国 → region码/时区/语言/MCC 映射 + 本地存储 + 请求参数改写
  - XNURLProtocol 转发前改写 device_region/app_region/sys_region/tz_name/timezone_offset/app_language/mcc_mnc 等
  - CommandEngine set_country/get_country 命令；浮窗国家选择点选即生效
  - **出口IP由用户小火箭(Shadowrocket)海外节点提供**；本层让环境信号与IP一致降风控
  - ⚠️ 边界：IP 仍由服务端判定账号区，伪装是"一致性加固"，不拦截注册请求
- 📦 节点台账 + GeoIP 门禁（后端已提交保留 a0b7cba，暂不扩展；祥哥走小火箭方案，设备端伪装为主）

- ✅ **第二批设备命令**（v1.4.54/1.4.55 已上线 VPS）：
  - 发视频指定选片（下载video_url存相册→自动选中）✅
  - `like_comment` 评论点赞（开评论→逐条点赞+下滑+随机间隔）✅
  - `open_live` 进直播间（主播主页→LIVE入口→验证）✅
  - `follow_user` 回关基础（打开用户+关注，引擎逐粉丝下发）✅
  - 粉丝私信：复用 send_dm + 任务引擎，无需新命令 ✅
  - 浮窗激活页"复制机器码(发客服人工激活)"按钮 ✅

- ✅ **第三批 · 任务中心前端**（已上线 VPS，commit 4426094）：
  - 批量任务页升级为统一引擎创建器：8类任务（评论点赞/回关/批量关注/点赞/评论/私信/发视频/采集）
  - 目标来源：数据组（采集分组下拉）或手动输入；数量/间隔/设备/发视频标题
  - 创建即启动；done/total 进度 + last_log 实时；启动/暂停/停止/恢复；8s 轮询
  - 验证通过：数据组解析 3 单元、引擎逐条下发、进度实时、停止生效

### 进行中 / 待做（按四批顺序）
- ⏳ v1.4.53 真机测试：set_country 环境伪装 + 小火箭海外节点配合
- ⏳ 浮窗补丁A 剩余：运行监控卡片/快捷指令页/养号实时行/APIID显示
- ⏳ 第三批剩余：指定视频评论复合命令（open_video+comment 一次下发）
- ⏳ 第一批第4项：后端 /api/translate
- ⏳ 第四批：P2扩展
- ⏳ 第一批第3项：切换国家后端（device.country + GeoIP + 前端引导）
- ⏳ 第一批第4项：后端 /api/translate
- ⏳ 第二批：设备端命令（发视频选片/like_comment/open_live/回关/dm_fans）+ 浮窗补丁A
- ⏳ 第三批：任务编排+前端（评论点赞/回关私信/视频评论等任务页）
- ⏳ 第四批：P2扩展（头像链接/人工激活代绑/分组去重/打码平台/翻译）

### P0 真机待验证（依赖祥哥设备，与开发并行）
互动养号崩溃 / 账号资料显示 / 采集粉丝 / 直播间检测 / 备份去重 / 评论发布真实性

### 版本基线
- 设备 v1.4.52（iphone_780EF63F，反馈回路打通）
- 后端 v1.3.0（FastAPI + SQLite，VPS 192.129.210.52）
- 前端 React（login/）
