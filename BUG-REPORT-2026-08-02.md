# XNOW 云控系统 前后端 Bug 审查报告

> 审查日期: 2026-08-02
> 审查范围: 前端(control.html + iOS浮窗 + 插件) + 后端(全部路由/模型/安全)
> 方式: 2 个专项审查代理 + 人工验证

---

## 🔴 CRITICAL（必须立即修复）

### C1. 控制面板 XSS（设备数据注入 innerHTML）
- **位置**: `backend/static/control.html:273`
- **问题**: 5秒轮询把设备字段拼进 `innerHTML`，未转义
  ```js
  document.getElementById('deviceStatus').innerHTML = `...设备:${dev.device_id||dev.name} App:${dev.app_version||'—'}`;
  ```
  `device_id`/`name`/`app_version` 都是设备可控制的（自动注册时原样入库）
- **攻击**: 恶意设备注册为 `x"><img src=x onerror=...>` → 注入admin页面 → 窃取 localStorage token
- **方案**: 改用 `textContent` 或 DOM API；设备字段加转义函数

### C2. 健康检查路径（已核实为稳健性小问题，非阻断）
- **位置**: `XNURLProtocol.m:45` 探测 `/health`，后端只有 `/api/health`
- **现状**: `/health` 被 SPA 兜底返回 index.html(200)，所以连接**实际可用**（用户看到"服务器可达"）
- **风险**: 若 SPA 兜底移除则连接断裂；且 `/health` 返回 HTML 而非 JSON 语义不对
- **方案**: 探测改 `/api/health`（返回真实 JSON 健康检查）

---

## 🟠 HIGH（尽快修复）

### H1. 控制面板 token 过期无法恢复
- **位置**: `control.html:244-250`
- **问题**: 401 只打日志不清 token → 页面永久失效，刷新也没用（ensureLogin 信任任意 token）
- **方案**: 401 时清 token + 重新登录弹窗；启动时验证 token 有效性

### H2. 指令执行结果恒显示"✅"（假成功）
- **位置**: `XNOWER.m:392`
- **问题**: `result[@"success"]` 恒为 nil（CommandEngine 返回 `@"status"` 键）→ 恒"✅"
- **风险**: 失败的点赞/发视频/切号显示成功，运营误判
- **方案**: 检查 `result[@"status"] == @"success"` 而非不存在的 success 键

### H3. 心跳定时器每次重连泄漏
- **位置**: `XNOWER.m:435-464`
- **问题**: startHeartbeat 每次创建新 timer，旧的从不 cancel → 重复 ping + 状态上报
- **方案**: 属性持有 timer，start/stop 时 cancel 旧的

### H4. 浮窗菜单指令映射错误
- **位置**: `XNFloatingPanel.m:653-677`
- **问题**: "关闭服务器链接"→下滑、"下载无水印视频"→智能浏览、"采集点赞"→采集粉丝
- **方案**: 加独立 delegate 回调，正确映射到真实操作

### H5. 绑定设备编号后指令丢失
- **位置**: `ws.py:391-396` + `XNOWER.m`
- **问题**: 绑定编号把 DB `name` 改成编号，但设备仍按旧 `iphone_xxx` 轮询 → 指令入队到错误 key
- **方案**: 不改 name，存独立 device_code 列；或绑定后设备立即重连新编号

### H6. WS 跨事件循环发指令丢命令
- **位置**: `devices.py:240` + `nurture.py:130`
- **问题**: 同步端点用 `asyncio.new_event_loop()` 发 WS → 跨loop冲突，WS 设备丢指令
- **方案**: `batch_dispatch` 改 async def；调度器用 asyncio 后台任务

### H7. 设备上报账号可跨租户篡改
- **位置**: `ws.py:102-147`
- **问题**: `_upsert_account` 查账号无 api_id 过滤，且可 mass-assign api_id
- **方案**: 按设备租户过滤 + 阻止 api_id 写入

### H8. 派发指令未校验目标设备归属
- **位置**: `video_posts/dm_tasks/quick_commands/nurture/device_commands`
- **问题**: 只校验资源归属，不校验 `device_id` 归属 → 可驱动别人设备
- **方案**: 派发时 `ensure_owned(device, user)`

### H9. HTTP 轮询设备永不标记离线
- **位置**: `ws.py:285-320`
- **问题**: 只有 WebSocket 断开才设 is_online=False，HTTP 设备掉线永远显示在线
- **方案**: 后台巡检任务（last_online 超时 → 离线）

### H10. 禁用用户 token 仍有效
- **位置**: `dependencies.py:18-33`
- **问题**: JWT 校验无 `is_active` 检查
- **方案**: 加 `if not user.is_active: 401`

---

## 🟡 MEDIUM（尽快处理）

| # | 问题 | 位置 | 方案 |
|---|------|------|------|
| M1 | 批量采集同请求内不去重 | collected_data.py | 加 seen 集合 |
| M2 | batch_import 返回他人账号 | accounts.py:204 | 按租户过滤 |
| M3 | dispatch_accounts 覆盖 account_count | accounts.py | 重算计数 |
| M4 | CSV 空数字格崩溃 | accounts.py:188 | try/except |
| M5 | 未鉴权上报端点 | device_commands.py | 加鉴权 |
| M6 | 设备可自定 api_id 绑定 | ws.py | 校验绑定 |
| M7 | CORS 全开+credentials | main.py | 收紧 |
| M8 | 养号计划不自动完成(end_date) | nurture.py | 检查 end_date |
| M9 | has_credentials 筛选破坏分页 | accounts.py | SQL 层过滤 |
| M10 | SPA 路径用 prefix 判断 | main.py:105 | commonpath |
| M11 | pydantic 2.12 需 Py3.9+ | requirements.txt | 降级或升级 VPS |
| M12 | DB 会话泄漏 | connection_manager/ws | try/finally |
| M13 | 面板养号/发视频选错设备 | control.html | 校验选中设备 |
| M14 | 立即发布重复派发已完成任务 | control.html | 过滤 pending |
| M15 | 心跳/轮询 401 持续刷屏 | control.html | 401 停止轮询 |
| M16 | 浮窗拖动手势抢滚动 | XNFloatingPanel | 展开时禁用拖拽 |

---

## ⚪ LOW

| # | 问题 |
|---|------|
| L1 | api_id 生成非原子（并发碰撞） |
| L2 | 登录限流字典无限增长 |
| L3 | send_or_enqueue 恒返回 True 误导 |
| L4 | 设备分组无租户隔离 |
| L5 | update_account credentials 字符串绕过加密 |
| L6 | admin 导入账号 api_id 为空 |
| L7 | _upsert_account 并发唯一约束竞争 |
| L8 | bind_info 改名导致 WS key 失配 |
| L9 | get_online_devices 死代码 |
| L10 | 素材批量导入不更新计数 |
| L11 | 素材列表跨租户计数泄漏 |
| L12 | 养号 daily_actions 未校验 |
| L13 | 调度器无关闭钩子 |
| L14 | 加密失败静默回明文 |
| L15 | 采集 followers 未类型校验 |
| L16 | scheduled_at 时区不一致 |
| L17 | _sendCommandToBackend 硬编码明文IP |
| L18 | 摇一摇恢复是死代码(NSObject非UIResponder) |
| L19 | keyWindow 已废弃 |
| L20 | 日志窗口/坐标硬编码不适配旋转 |

---

## 📌 修复优先级建议

**立即（阻断级）**：
1. C1 控制面板 XSS 转义
2. H2 指令结果真假状态
3. H6 WS 跨loop 丢指令
4. H7/H8 设备/账号归属校验
5. H10 is_active 检查
6. C2 健康检查改 /api/health

**本周**：
7. H3/H4/H5 心跳/菜单映射/绑定编号
8. H1 控制面板 token 恢复
9. H9 离线巡检
10. M1-M12 后端健壮性

**下周**：
11. M13-M16 + LOW 项
12. 8 个未隔离路由补租户

---

## ✅ 已确认正常的功能（实测）

- 设备鉴权（v1.3.30+ 带 secret 轮询）
- 15+ 指令下发执行回传
- 采集数据入库/去重/筛选/统计
- 素材分组模板
- 视频/私信/养号/快捷指令 API
- 凭证加密 / 登录限流 / 路径穿越防护
