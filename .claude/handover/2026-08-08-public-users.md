# 接力开发笔记：2026-08-08 公共用户库（PPT 全功能计划第一批第1项）

> 交接：从"PPT 全功能对账"转入开发，第一个交付的功能
> 关联计划：`PLAN-2026-08-08-PPT全功能对账与开发计划.md`（十节，含验收报告）

## 📌 完成状态

| 项 | 状态 |
|---|---|
| 功能 | **公共用户库完整版**（PPT S39 商业核心） |
| 版本 | 后端 commit `dd3e0a4`(主体) + `026ed57`(打标修复)；前端 `c2786cc` |
| 部署 | VPS 已上线（后端 + 前端），生产 DB 已清测试数据 |
| 验证 | ✅ 全链路通过（含真实 qwen-vl 打标 2.6s） |

## 🎯 交付内容

- **后端 5 端点**（/api/biz/v2/public-users/）：
  - `GET /public-users/` 跨租户筛选（性别/国家/粉丝区间/关键词/打标状态/昵称搜索）
  - `GET /public-users/stats/` 总数/已打标/性别/国家分布
  - `POST /public-users/feed/` 采集数据投喂（脱敏+aweme全局去重+质量过滤）
  - `POST /public-users/copy/` 复制公共库到当前租户分组（source_type=public）
  - `POST /public-users/tag/` AI头像打标（qwen-vl）
- **模型**：`public_users` 13列，仅公开资料，不含任何凭证
- **前端**：`PublicLibrary.tsx`（统计卡片/多维筛选/投喂弹窗/AI打标/勾选复制）
- **配置**：config.py 加 DASHSCOPE_*，VPS /opt/xnow-flow/.env 已配置 key

## 🔑 关键经验（血泪坑）

1. **auth 登录路径是 `/api/auth/login`**（不是 biz/v2），响应字段是 `token`（不是 access_token）
2. **部署后必须重启**：VPS 没装 lsof，`kill $(lsof -ti:8000)` 静默失败导致旧进程带老代码继续跑。正确姿势：`pkill -f "uvicorn main:app"` 后重启
3. **plink `-m` 脚本遇 `nohup ... &` 输出会截断**：重启后再单独 `pgrep`/`curl` 确认
4. **Windows 本地 Python 环境坏**（cryptography/pip 缺模块）→ 后端验证一律在 VPS 做，本地只 py_compile
5. **pscp `-r` 到不存在目录报 "unable to open"**：先 mkdir 再传；前端 assets 用"传 assets_new → mv 切换"原子更新
6. **AI 打标失败不标记 ai_tagged**（否则配 key 后无法重试）；无 key 直接 400 提示
7. **投喂后"复制"必然命中去重**（因为自己投喂的 aweme 已在采集库）——跨租户复制才是 INSERT 场景，测试要用异租户数据

## ⚠️ 运维备注

- **生产 DB 现 public_users 为 0 条**：等真实采集数据到位后，前端「公共用户库」页点"投喂公共库"→ AI打标 → 筛选 → 复制到分组
- VPS `.env` 已写 DASHSCOPE key（sk-ws-...，长度117）。**换 key 或轮换时记得同步 VPS**
- 前端入口：后台左侧"内容"组 →「公共用户库」

## 🛠 下一步（按计划顺序）

1. **第一批第2项**：统一任务引擎基础模型（type枚举 + 账号组/数据组/素材组 + 风控上限），顺带"任务状态查询接口"供手机端监控卡片
2. **第一批第3项**：切换国家后端（device.country + GeoIP + 前端引导）
3. **第一批第4项**：后端 /api/translate
4. P0 真机验证项（依赖祥哥设备）并行
