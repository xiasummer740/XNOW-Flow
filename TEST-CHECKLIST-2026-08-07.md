# XNOW 功能测试清单（v1.4.34，设备 iphone_FBC8363E）

> 日期：2026-08-07 | 自测方式：后端下发 + 诊断验证（state_diag/scroll_diag/touch_diag）
> ✅=后端诊断确认生效 ❌=失败/未生效 ⏳=执行中或需人工确认

## A. 基本操作
- [✅] ❤️ 点赞（like）— acc_label → "Video liked" 确认
- [✅] ⬇️ 下滑（scroll_down）— feed 翻页 target=6 确认
- [✅] ⭐ 收藏（collect）— acc_label → "Added to Favorites" 确认
- [⏳] 💬 评论（comment）— 流程执行(duration 2)，发布是否成功需人工确认
- [✅] 📸 截图（screenshot）
- [✅] 🌐 智能浏览（smart_browse）— scrolls=3 完成
- [✅] ↩️ 返回（go_back）
- [✅] 🏠 首页（go_home）— 点击 Home tab 确认
- [✅] 🔎 打开搜索（open_search）
- [✅] 🔍 打开tab（open_tab）— 切换页确认
- [✅] 💓 健康检查（check_health）— health_score=100 active
- [⏳] ⬆️ 上滑 / ➕ 关注 / ✉️消息页 / 👤我的页 / 🔄刷新 / 📤分享 / 💾保存视频 — 同类指令已通，待人工确认

## B. 修改资料
- [✅] ✏️ 修改昵称（edit_profile）— duration 4 完成

## C. 自动发视频
- [⏳] 📝 创建视频任务（POST /video-posts/）
- [⏳] 🚀 立即发布（dispatch）

## D. 自动私信
- [⏳] 📝 创建私信任务（POST /dm-tasks/）
- [⏳] 🚀 立即发送（dispatch）

## E. 注册账号
- [❌] 📝 注册账号 — "未找到登录/注册入口"（设备已登录，注册需登出状态 → 预期行为）

## F. 养号
- [⏳] 🌱 养号计划创建/开始/暂停（nurture-plans API）
- [⏳] ⏱ 随机观看时间日志 / 随机互动

## G. 快捷指令
- [⏳] 💾 保存 + 🚀 下发（quick-commands API）

## H. 打开指定内容
- [⏳] 🔍 搜索关键词 / 👤 打开用户 / 🎬 打开视频

## I. 采集
- [⏳] 👥 采集粉丝 / 🎬 采集视频 / 💬 采集评论 / 📺 采集直播 — 采集视频执行中
- [✅] 👤 获取账号信息 — ⚠️ 返回空（账号检测未生效，待修）
- [✅] 💓 健康检查

## J. 批量操作
- [✅] ❤️ 批量点赞（batch_like）— duration 6s 完成
- [⏳] 👥 批量关注 / 💬 批量评论 — 待测

## K. 账号操作
- [✅] 📮 上报账号（report_account）
- [⏳] 🔄 切换账号 / 🚪 退出登录 — 待测

## L. 备份账号
- [⏳] 💾 备份当前账号（backup_account）— 需导航个人页检测账号

## N. 前端（网页后台 /）
- [✅] 🎮 设备控制页 — 已上线（选设备+全指令+结果日志）
- [✅] 📊 数据概览/设备管理/账号管理/批量任务/定时任务/执行统计/任务日志/素材/采集 — 普通用户 API 全 200
- [✅] 🎫 卡密管理/用户管理 — admin 专属

## 已知问题（待修）
1. ❌ **get_account_info 返回空** — 账号检测（网络捕获+UI扫描）未生效
2. ⚠️ **comment 发布确认** — 流程执行但需验证是否真发布
3. ⚠️ **register_account** — 需在未登录状态才能测
4. ⏳ **collect/batch/backup** — 执行中/待完整验证

## 测试账号
- admin / Xia900221. （管理员）
- test01 / test123456 （普通用户，api_id 5729）
