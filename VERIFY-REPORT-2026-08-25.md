# 真机验证报告 · 2026-08-25 · v1.4.121

> 设备：`iphone_A6D8F9B4`（卡密 7YDYWYSKMKZAH06Q，active，剩余约 354 天）
> 方式：VPS 远程下发命令 + server.log 取证（不含隐私值）
> 遵守攒批纪律：本次仅验证，未发新版本

## 验证结果汇总

| # | 功能 | 结果 | 证据 |
|---|------|------|------|
| 1 | 设备健康 | ✅ 通过 | `check_health {'status':'active','health_score':100,'issues':[]}` |
| 2 | 卡密激活 | ✅ 通过 | licenses 表 active，绑定 A6D8F9B4，remark=rebind-20260825 |
| 3 | 备份账号 | ✅ 通过 | `backup_account {'status':'success','message':'已备份账号 #1 登录态','account_id':1}`（15:15 与 15:25 两次均成功） |
| 4 | 智能浏览（防闪退） | ✅ 通过 | `smart_browse {'status':'success','likes':3,'follows':3,'scrolls':14,'duration':104}` 跑满无闪退 |
| 5 | 关注（自动） | ✅ 通过 | 智能浏览内部自动关注 3 个账号成功（走 `_performFollow`） |
| 6 | 国家显示 | ❌ 121 仍空 | backup 结果无 country 字段；**v1.4.122 cookie 兜底已备待发** |
| 7 | 修改资料 | ⏳ 待验 | 涉及真实账号数据，需祥哥配合给测试用户名或 Web 端操作 |

## 关键取证

- **后端已确认重启成功**：licenses.py 设备漂移自动重绑已部署（PID 868282，`Application startup complete`），设备持续 poll 正常。
- **国家 122 必成证据**：diagnostic cookies 已含 `store-country-code@.tiktok.com/.tiktokv.com/.tiktokw.us/.tiktokw.eu/.tiktokv.us` 全部带值 → `_countryFromCookies` 兜底必读到国家码。
- **历史对照**：14:23 曾有 `backup_account failed '未检测到登录态'`（121 装机初态候选扫描失败），15:15 起稳定 success —— 121 的 archive 解析修复生效。
- **修改资料失败根因实锤（新发现）**：2026-08-25 下发 `edit_profile` 改昵称 outshine1 → 控件树仍显示 Outshine/@outshine83。根因=编辑按钮 accId `user_info_manage_edit_profile`（下划线）与代码 label 匹配 `"Edit profile"`（带空格）不命中 → 坐标兜底 (374,340) 点偏 → 编辑页没打开。**v1.4.123 已修**（accId 优先定位），已编译打包上传。

## 攒批清单（当前待发）

1. **国家 cookie 兜底（v1.4.122）** —— 已编译打包上传 static/，验证证据链完整
2. **修改资料编辑按钮定位（v1.4.123）** —— 已编译打包上传 static/（md5 7890335fa683284050071f3d2a4a76ed），待装机验证
3. **device_id 漂移自动重绑（后端）** —— 已部署生效，待一次重装实测验收
4. **后台独立关注命令** —— 智能浏览内已通过（follows:3），单独 follow_user 实测：导航 outshine1 失败（停在原页，误命中「0, Following,」计数标签），待 follow_user 导航修正确认
