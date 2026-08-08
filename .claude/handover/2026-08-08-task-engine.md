# 接力开发笔记：2026-08-08 统一任务引擎（第一批第2项）

> 交接：PPT 全功能计划第一批第2项交付
> 上项：公共用户库（`2026-08-08-public-users.md`）

## 📌 完成状态

| 项 | 状态 |
|---|---|
| 功能 | **统一任务引擎基础模型**（PPT 全部"指令创建"的统一底座） |
| 版本 | commit `c62d34a` |
| 部署 | VPS 已上线，task-engine 线程运行中 |
| 验证 | ✅ 10 项全过（风控/完成/停止/数据组/进度/审计） |

## 🎯 交付内容

**Task 模型扩展**（tasks 表 +8 列）：`config`(JSON) / `total` / `done` / `fail_count` / `last_log` / `error` / `started_at` / `next_dispatch_at`

**task_engine.py**（后台线程，3s tick）：
- running 任务按随机间隔 `[min_interval, max_interval]` 逐单元下发
- 风控钳制：like/comment_like→300，follow/follow_back→200（PPT 参考值）
- 下发 payload：`{type:command, action, params:{unit_param: 单元}}`
  - 类型→action 映射 + 单元参数名（comment→text, dm→content, post_video→video_url, 其余→target）
- 每单元写 TaskExecution 审计；进度 done/total + last_log 实时更新
- 完成后自动 status=done

**tasks 路由扩展**：
- `POST /tasks/` 创建（兼容旧前端简单字段，新增 config）
- `POST /tasks/{id}/start/` 启动（`target_group` 从采集数据组解析 targets = 数据组引用）
- `POST /tasks/{id}/stop|pause|resume/`
- `GET /tasks/status/running/` 运行中任务（**手机端运行监控卡片订阅点**）
- `GET /tasks/` 列表带引擎字段

## 🔑 关键经验

1. **async 下发**：`send_or_enqueue_command` 是 async，后台线程用 `asyncio.new_event_loop()` + `run_until_complete`（照抄 nurture 调度模式）
2. **设备不可达=入队成功**：`enqueue_command` 对任意 device_id 建内存队列，测试用假设备 TEST_DEV 不会误触真机
3. **风控钳制在创建+启动两处**（config.risk_cap 优先，无则类型默认值）
4. **数据组引用**：`start` 传 `target_group` → 从 collected_data 按 api_id+group 解析 targets（GRP aweme_id 优先）

## ⚠️ 运维备注

- task-engine 线程随后端启动/关闭（main.py）
- 生产 tasks 表原有 104 条真实任务不受影响（新列默认值）
- 测试数据已清理（tasks/executions/collected_data）

## 🛠 下一步（按计划顺序）

1. **第一批第3项**：切换国家后端（device.country + GeoIP + 前端引导）
2. **第一批第4项**：后端 /api/translate
3. 第二批设备命令就绪后（like_comment 等），统一引擎可直接承载对应任务类型
