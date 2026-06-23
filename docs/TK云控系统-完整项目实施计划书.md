# TikTok 苹果真机云控系统 — 零基础完整项目实施计划书

> **版本**: v3.0 | **日期**: 2026-06-23
> **品牌**: XNOW 云控
> **目标**: 基于 iOS 免越狱注入技术，搭建带品牌定制、安全认证、完整功能的 TikTok 苹果真机云控系统
> **参考后台**: https://wsyufu.net（TK_iOS云控管理系统）
> **前端构建工具**: https://github.com/firecrawl/open-lovable
> **你的设备**: Win11 + 云服务器 + 软路由 + iPhone 8

---

## 📋 目录

1. [项目全景概述](#1-项目全景概述)
2. [一键架构图（核心）](#2-一键架构图核心)
3. [参考后台功能清单（wsyufu.net）](#3-参考后台功能清单wsyufunet)
4. [物料检查清单](#4-物料检查清单)
5. [🎨 XNOW 品牌视觉系统](#5-xnow-品牌视觉系统)
6. [阶段一：开发环境搭建（第1天）](#6-阶段一开发环境搭建第1天)
7. [阶段二：iPhone 8 越狱 & 纯净包提取（第2天）](#7-阶段二iphone-8-越狱--纯净包提取第2天)
8. [阶段三：🔥 用 open-lovable 构建 XNOW 云控网站（第3-4天）](#8-阶段三用-open-lovable-构建-xnow-云控网站第3-4天)
9. [阶段四：云服务器后端 API 开发 + 安全认证（第5-6天）](#9-阶段四云服务器后端-api-开发--安全认证第5-6天)
10. [阶段五：iOS 注入插件（Tweak）开发（第7-9天）](#10-阶段五ios-注入插件tweak开发第7-9天)
11. [阶段六：打包、签名 & 安装（第10天）](#11-阶段六打包签名--安装第10天)
12. [阶段七：前后端联调 + 功能全量扩展（第11-15天）](#12-阶段七前后端联调--功能全量扩展第11-15天)
13. [阶段八：🔐 安全加固 + HTTPS + 多设备扩容（第16-18天）](#13-阶段八安全加固--https--多设备扩容第16-18天)
14. [阶段九：运维与监控（第19-20天）](#14-阶段九运维与监控第19-20天)
15. [AI 提示词大全](#15-ai-提示词大全)
16. [成本核算](#16-成本核算)
17. [🚨 特级警告与避坑指南](#17-特级警告与避坑指南)
18. [故障排查手册](#18-故障排查手册)

---

## 1. 项目全景概述

### 1.1 我们要做什么

搭建一套完整的 **"网站后台 ↔ 云服务器 ↔ iPhone 真机"** TikTok 云控系统。

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  你打开浏览器看到的网站（前端）                                        │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  TK云控后台 (React 版，用 open-lovable 克隆 wsyufu.net 风格)   │   │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐        │   │
│  │  │ 数据概览 │ │ 设备管理  │ │ 批量任务  │ │ 账号管理  │ ...    │   │
│  │  │ 统计卡片 │ │ 设备列表 │ │ 关注/私信 │ │ TK账号   │        │   │
│  │  │ 在线状态 │ │ 下发任务 │ │ 发布作品  │ │ 绑定设备  │        │   │
│  │  └─────────┘ └──────────┘ └──────────┘ └──────────┘        │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                          │ 调用 API                                  │
│                          ▼                                          │
│  云服务器后端 (FastAPI)                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  设备管理 API │ 任务调度 │ 账号管理 │ 数据统计 │ WebSocket    │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                          │ WebSocket 长连接                          │
│                          ▼                                          │
│  软路由 (海外纯净 IP 隔离)                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  MAC 绑定 │ 住宅代理 │ 全局强制代理 │ 流量隔离                    │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                          │ Wi-Fi                                    │
│                          ▼                                          │
│  iPhone 8 (已安装魔改版 TikTok)                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  TikTok App + 注入插件 (WebSocket 客户端 + 自动化执行)          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 网站（前端）是整个系统的控制中心

这是你每天面对的东西——**在浏览器里打开的网页**，而不是手机 App。

| 你点这个按钮... | 网站做了什么 | 手机上发生了什么 |
|:---------------:|-------------|-----------------|
| 【一键下滑】 | 后端发 WebSocket 指令 | TikTok 自动翻页 |
| 【批量关注】 | 调 API → 下发给指定设备 | 自动打开关注列表 |
| 【发布作品】 | 上传视频 → 推送到手机 | 自动打开相册发布 |
| 【数据看板】 | 调统计 API | 显示执行数据 |

### 1.3 怎么构建这个网站？

我们要用 **firecrawl/open-lovable** 来构建前端。这是一个 AI 驱动的工具：

```
1. 给它一个网址（参考 wsyufu.net 的设计）
2. 它用 AI 自动生成一个 React 网站
3. 你通过聊天让 AI 修改→直到满意
4. 最终产物：一个完整的、可直接部署的 React 前端
```

> 💡 相当于：你不用手写一行 HTML/CSS，AI 帮你把 wsyufu.net 的界面"克隆"下来，你只需要改背后的 API 地址指向你自己的服务器。

---

## 2. 一键架构图（核心）

### 2.1 三体合一结构

```
┌────────────────────────────────────────────────────────────────────────────┐
│                                                                            │
│  第一体：前端网站 ←─── 这是你的工作台                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 技术：React + TypeScript + Tailwind CSS                              │  │
│  │ 构建：用 firecrawl/open-lovable 克隆 wsyufu.net 生成                  │  │
│  │ 部署：Vercel / Nginx / 云服务器上直接跑                               │  │
│  │ 功能：数据看板 / 设备管理 / 任务管理 / 账号管理 / 素材管理 / 日志       │  │
│  └──────────────────────────┬───────────────────────────────────────────┘  │
│                              │ HTTP API                                   │
│                              ▼                                             │
│  第二体：后端 API ─── 这是你的大脑                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 技术：Python FastAPI + SQLite/PostgreSQL + WebSocket                 │  │
│  │ 部署：云服务器 (systemd 持久运行)                                     │  │
│  │ 功能：设备连接管理 / 指令下发 / 任务调度 / 数据存储 / 统计             │  │
│  └──────────────────────────┬───────────────────────────────────────────┘  │
│                              │ WebSocket 长连接                           │
│                              ▼                                             │
│  第三体：iOS 插件 ─── 这是你的手                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 技术：Theos + Objective-C + WebSocket 客户端                         │  │
│  │ 载体：注入到 TikTok 安装包内，通过开发者证书签名安装到 iPhone          │  │
│  │ 功能：接收指令 → 执行自动化操作 → 回传结果                            │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 访问流程（你每天怎么用）

```
1. 打开电脑浏览器 → 输入 http://你的云控网站域名
2. 看到登录页面 → 输入管理员账号密码
3. 进入【数据概览】→ 看到所有设备在线状态、今日执行统计
4. 点【设备管理】→ 看到 iPhone 列表，每个手机后面有操作按钮
5. 点【一键下滑】→ 手机端 TikTok 自动翻页
6. 点【批量任务】→ 创建新任务（关注100个用户）
7. 任务自动执行 → 去【执行统计】看结果
```

整个过程你在浏览器里操作，手机在机房里自动响应。

### 2.3 数据流

```
【前端 React 页面】
   点击按钮 → fetch POST /api/action/device1/scroll_down
       │
       ▼
【后端 FastAPI】
   收到请求 → 查找 device1 的 WebSocket 连接
   发送 JSON → {"action": "scroll_down"}
       │
       ▼
【WebSocket 长连接】（实时双向通信）
   穿越云服务器 → 软路由 → Wi-Fi → iPhone
       │
       ▼
【iOS 注入插件】
   收到指令 → 解析 JSON → 调用 TikTok 内部 ViewController 方法
   执行成功 → 回传 {"status": "success"}
       │
       ▼
【后端记录】
   写入数据库 → 更新任务状态 → 前端下次刷新时显示结果
```

---

## 3. 参考后台功能清单（wsyufu.net）

以下是从参考后台提取的完整功能列表，**最终目标**是复现这些功能在你的网站上：

### 3.1 导航结构

```
TK_iOS云控 (品牌名)
├── 📊 数据概览 (Dashboard)
│   ├── 统计卡片：设备总数 / 在线 / 空闲 / 执行中 / 离线
│   ├── 今日执行次数
│   └── 账号状态分布
│
├── 📋 批量任务 (Task Management) ←── 核心功能
│   ├── 互动类：批量关注 / 批量私信 / 评论点赞 / 取消关注 / 指定视频评论
│   ├── 发布类：发布作品 / 隐藏全部视频
│   ├── 采集类：用户采集 / 采集视频评论 / 采集博主视频 / 本地采集点赞 / 本地采集关注
│   ├── 账号类：修改账号资料 / 自动上号 / 开启2FA / 移除历史设备
│   └── 养号：智能养号
│
├── ⏰ 定时任务 (Scheduled Tasks)
│   ├── 一次性定时任务
│   └── 循环周期性任务（支持 cron 表达式）
│
├── 📈 执行统计 (Execution Statistics)
│   ├── 按天/周/月统计
│   └── 成功率/失败率
│
├── 📝 任务日志 (Task Logs)
│   ├── 按设备/任务类型/时间筛选
│   └── 执行详情查看
│
├── 📱 设备管理 (Device Management) ←── 核心功能
│   ├── 设备列表（编号/机器码/分组/在线状态/运行状态/今日任务/绑定账号）
│   ├── 分组管理
│   ├── 批量修改分组 / 批量删除
│   └── 下发任务按钮
│
├── 👤 账号管理 (Account Management)
│   ├── 账号列表（TKUID/昵称/TK号/状态/安全信息/设备/粉丝/今日涨粉/健康分/地区/标签）
│   ├── 账号仓库
│   ├── 账号登录（自动上号）
│   └── 筛选：账号状态 / 设备 / 标签 / 国家地区 / 2FA状态
│
├── 🎬 素材管理 (Media Management)
│   ├── 素材文件（视频/图片上传）
│   ├── 文字模板（评论话术、私信内容）
│   ├── 分组管理
│   └── 使用统计
│
├── 📊 采集数据 (Collected Data)
├── 📢 公告中心 (Announcements)
├── 💬 反馈中心 (Feedback)
├── ⚙️ 回复配置 (Reply Configuration)
├── 🔧 设置中心 (Settings)
└── 📖 使用教程 (Tutorial)
```

### 3.2 设备管理表格字段

| 字段 | 说明 |
|------|------|
| 序号 | 自动编号 |
| 手机编号 | 自定义名称（如 iPhone_001）|
| 设备机器码 | 设备唯一标识（64位哈希）|
| 所属分组 | 如：美国组、英国组 |
| 在线状态 | 在线/离线 |
| 运行状态 | 空闲/执行中/锁定 |
| 今日任务 | 已执行任务数 |
| 绑定账号 | 关联的 TK 账号 |
| 标签 | 自定义标签 |
| App版本 | 插件版本号 |
| 操作 | 下发任务 / 编辑 / 删除 |

### 3.3 账号管理表格字段

| 字段 | 说明 |
|------|------|
| 账号信息 | 头像 + TKUID + 昵称 + TK号 |
| 状态 | 正常 / 风控 / 掉登录 / 已限流 |
| 安全信息 | 2FA开启状态 / 登录设备 |
| 设备 | 绑定的设备编号 |
| 粉丝 | 粉丝数量 |
| 今日涨粉 | 当日新增粉丝 |
| 健康分 | 账号健康评分 |
| 地区 | 目标国家 |
| 标签 | 自定义标签 |
| 更新时间 | 最后更新 |

---

## 4. 物料检查清单

### ✅ 你已有的

| 物料 | 用途 | 备注 |
|------|------|------|
| Windows 11 电脑 | 主控开发机 | 装 VS Code + WSL2 + Sideloadly |
| 云服务器 | 中控后台 | 推荐 Ubuntu 22.04/24.04，2核4G+ |
| 软路由（有）| 网络隔离 | 已配置 OpenWrt，关键！|
| iPhone 8（有）| 砸壳工具机 + 干活机 | 检查系统版本（iOS 15-16 最佳）|
| VS Code | 代码编辑器 | 已装 WSL 插件 |
| Claude + DeepSeek | AI 编程助手 | CC Switch 切换 |
| 海外住宅 IP（有）| 伪装网络环境 | 配置在软路由上 |

### 🛒 需要购买的

| 物料 | 预算 | 说明 |
|------|------|------|
| 空白 U 盘（4G+）| ~¥20 | 制作越狱引导盘 |
| 海外过期物理 SIM 卡 | ~¥10/张 | 淘宝搜"美国T-Mobile过期卡" |
| 苹果开发者证书 | ~¥30-100 | 淘宝搜"iOS个人开发者证书UDID签名" |
| USB-A to Lightning 数据线 | ~¥30 | 原装或绿联，越狱必须用 |

### 4.1 ✅ 核心机制：环境隔离 + 多账号同机运行

**参考后台的设计是：1台手机 → 多个独立环境 → 每个环境登录1个TK账号**

```
┌─────────────────────────────────────────────────────┐
│  iPhone 8 (1台物理设备)                              │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │  魔改版 TikTok（注入插件）                       │ │
│  │                                                  │ │
│  │  环境 #1 ─── 数据沙箱A ─── TK账号A ─── IP_A     │ │
│  │  环境 #2 ─── 数据沙箱B ─── TK账号B ─── IP_B     │ │
│  │  环境 #3 ─── 数据沙箱C ─── TK账号C ─── IP_C     │ │
│  │  ...                          ...                │ │
│  │  环境 #20 ── 数据沙箱T ─── TK账号T ─── IP_T     │ │
│  │                                                  │ │
│  │  自动切号：环境间互不干扰，数据完全隔离             │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

**这是怎么做到的？**（核心原理）

```
1. 插件修改 TikTok 的数据存储路径
   原本：/Documents/com.zhiliaoapp.musically/
   改成：/Documents/environments/env_001/com.zhiliaoapp.musically/
         /Documents/environments/env_002/com.zhiliaoapp.musically/
         /Documents/environments/env_003/...

2. 每个环境拥有完全独立的数据沙箱：
   □ 独立的 Cookies（登录态完全隔离）
   □ 独立的 Cache（视频缓存不交叉）
   □ 独立的 Preferences（语言/地区设置各自独立）
   □ 独立的 Keychain（账号密码不共享）

3. 自动切号 = 切换当前激活的环境
   手机当前显示的是"环境 #1"的 TikTok
   收到切号指令 → 保存环境 #1 状态 → 加载环境 #2 → 刷新界面
   看起来就像换了一台手机
```

**每个环境的网络隔离怎么做？**

| 方案 | 做法 | 效果 |
|:----:|------|------|
| ✅ 软路由 | 软路由为每个环境分配不同的出口IP | 环境A→IP_A, 环境B→IP_B, 完全隔离 |
| ⚠️ 小火箭 | 小火箭在手机端只能全局一个代理 | 所有环境共用同一个IP，无法隔离 |

> 这就是为什么参考系统 **推荐软路由**。小火箭能让手机翻墙，但不能让不同环境走不同IP。

**那参考后台能一台手机跑20个账号吗？**

```
可以！这就是"多账号矩阵管理"的含义：
一台手机 → 创建20个独立环境 → 每个环境登录1个TK账号
           → 软路由分配20个不同IP → 账号间完全隔离

不冲突的原因：
  TikTok 看到的是"20台不同的设备"
  （因为每个环境的沙箱数据不同，设备指纹也不同）
  而不是"同一台设备登录了20个账号"
```

**这才是正确的计划方向**——我之前写"一台手机最多5个账号"是错的，已修正。

### 4.2 软路由 vs 小火箭（Shadowrocket）网络方案对比

| 对比项 | ✅ 软路由（推荐） | ⚠️ 小火箭（备选）|
|:------:|:----------------:|:----------------:|
| 稳定性 | 7×24 不中断 | 手机杀后台会断连 |
| 检测风险 | 手机完全感知不到 | iOS 状态栏有 VPN 图标 |
| 后台保活 | 不需要 | 需配置后台刷新 |
| 成本 | 已有则免费 | App Store ¥28 购买 |
| WebSocket | 自动分流 | 需要手动配规则 |
| 🏁 **多环境IP隔离** | ✅ 每个环境可分配不同IP | ❌ **做不到**（手机全局只有一个代理）|

> **重要**：如果你的目标是跑 20 个环境，**必须用软路由**。小火箭能让手机翻墙，但不能让20个环境各走各的IP。
> 软路由的方案：为每个环境在路由器上建一个独立路由表，环境切换时自动切换出口IP。

**用小火箭的关键规则配置：**

```
小火箭配置必须添加以下规则（按优先级）：
  你的云服务器IP → DIRECT（直连，不走代理）
  ws://你的服务器IP → DIRECT
  api.tiktok.com → PROXY
  *.tiktokv.com → PROXY
  *.byteoversea.com → PROXY
  其他 → PROXY

这样魔改版 TikTok 的 WebSocket 到云控服务器走直连
TikTok 的 API 请求走海外代理
```

### 🔥 firecrawl/open-lovable 需要的 API

| API Key | 获取地址 | 费用 |
|---------|---------|------|
| FIRECRAWL_API_KEY | https://firecrawl.dev | 有免费额度 |
| GEMINI_API_KEY | https://aistudio.google.com/app/apikey | 免费 |
| 或 ANTHROPIC_API_KEY | https://console.anthropic.com | 付费 |

---

## 5. 🎨 XNOW 品牌视觉系统

> **在写任何代码之前，先把品牌调性定死。** 后面所有前端页面直接套用这套规范。

### 5.1 品牌名称与 Logo

| 项目 | 内容 |
|------|------|
| 品牌名 | **XNOW** |
| 中文名 | XNOW 云控 |
| 默认标题 | XNOW Cloud Control |
| Logo | 建议用文字 Logo（粗体 XNOW + 闪电/云朵图标）|
| Favicon | 用 X 字母变形或闪电图标 |

**Logo SVG 代码（给 AI 用的参考）：**

```svg
<!-- 简单的 XNOW 文字 Logo 示例 -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 50">
  <defs>
    <linearGradient id="xnowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />
    </linearGradient>
  </defs>
  <text x="10" y="35" font-family="Arial, sans-serif" font-weight="900" font-size="28" fill="url(#xnowGrad)">XNOW</text>
</svg>
```

### 5.2 🎨 完整配色方案

```
XNOW 品牌色板
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  主色渐变                                                │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  #667eea → #764ba2 (紫蓝渐变)                            │
│                                                          │
│  备选渐变                                                │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│  #667eea → #f093fb (紫蓝→粉紫)                           │
│                                                          │
│  辅助色                                                  │
│  ████████ #1a1a2e (深色背景)                             │
│  ████████ #16213e (侧边栏背景)                           │
│  ████████ #0f3460 (卡片背景)                             │
│  ████████ #e94560 (强调色/危险色 粉色)                   │
│  ████████ #4ecca3 (成功色 绿色)                          │
│  ████████ #ffd700 (警告色 金色)                          │
│                                                          │
│  文字色                                                  │
│  ████████ #ffffff (主文字)                               │
│  ████████ #a0aec0 (次要文字)                             │
│  ████████ #4a5568 (禁用文字)                             │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 5.3 CSS 渐变背景方案

前端页面用的渐变背景（Tailwind CSS）：

```css
/* XNOW 渐变背景 - 用在登录页、卡片头、品牌区域 */

/* 主渐变：紫蓝渐变 */
.xnow-gradient {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

/* 深色模式渐变背景 */
.xnow-bg-dark {
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
}

/* 卡片发光边框 */
.xnow-card {
  background: linear-gradient(135deg, #1a1a2e, #16213e);
  border: 1px solid rgba(102, 126, 234, 0.2);
  box-shadow: 0 8px 32px rgba(102, 126, 234, 0.1);
}

/* 按钮渐变 */
.xnow-btn-primary {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  transition: all 0.3s ease;
}
.xnow-btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 25px rgba(102, 126, 234, 0.4);
}

/* 品牌色文字 */
.xnow-text {
  background: linear-gradient(135deg, #667eea, #764ba2);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
```

### 5.4 给 AI 的品牌定制 Prompt

在 open-lovable 中告诉 AI：

```
请将整个应用的品牌改为 "XNOW"。

具体要求：
1. 网站标题改为 "XNOW 云控"（英文: XNOW Cloud Control）
2. 左侧导航顶部品牌名改为 "XNOW"，使用紫蓝渐变文字（#667eea → #764ba2）
3. 浏览器标签页标题改为 "XNOW 云控"
4. 网站图标（favicon）用 XNOW 缩写
5. 主题色改为：
   - 主色：#667eea
   - 渐变色：linear-gradient(135deg, #667eea, #764ba2)
   - 深色背景：#1a1a2e
   - 侧边栏背景：#16213e
   - 强调色：#e94560（红色/粉色）
   - 成功色：#4ecca3（绿色）
6. 所有按钮使用紫蓝渐变背景
7. 登录页背景使用深色渐变（#1a1a2e → #16213e → #0f3460）
8. 卡片使用半透明毛玻璃效果（glassmorphism）
9. 表格头使用渐变背景色
10. 所有加载动画使用品牌紫色
```

### 5.5 前端 Tailwind 配置

```javascript
// tailwind.config.js 中的主题扩展
module.exports = {
  theme: {
    extend: {
      colors: {
        xnow: {
          primary: '#667eea',
          secondary: '#764ba2',
          dark: '#1a1a2e',
          sidebar: '#16213e',
          card: '#0f3460',
          danger: '#e94560',
          success: '#4ecca3',
          warning: '#ffd700',
        },
      },
      backgroundImage: {
        'xnow-gradient': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        'xnow-dark': 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)',
      },
    },
  },
};
```

---

## 6. 阶段一：开发环境搭建（第1天）

> ⏱ 预计耗时：3-4 小时

### 6.1 开启 WSL2（Windows Linux 子系统）

```
1. 在 Win11 搜索栏输入 "启用或关闭 Windows 功能"
2. 勾选：
   ☑ 适用于 Linux 的 Windows 子系统
   ☑ 虚拟机平台
3. 点击确定 → 重启电脑
4. 打开 Microsoft Store → 搜索 "Ubuntu" → 安装 Ubuntu 24.04 LTS
5. 打开 Ubuntu → 设置用户名和密码
```

### 6.2 安装 VS Code + 插件

```
1. 打开 VS Code → 扩展 → 安装 "WSL"（Microsoft 官方）
2. 安装 "Remote - SSH"（连接云服务器用）
3. 点左下角 "><" → Connect to WSL
4. 左下角显示 "WSL: Ubuntu" → 成功
```

### 6.3 WSL 内安装基础工具

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install python3-pip python3-venv git curl wget -y
```

### 6.4 云服务器基础配置

```bash
# SSH 连接你的云服务器
ssh root@你的服务器IP

# 安装基础环境
apt update && apt upgrade -y
apt install python3-pip python3-venv git nginx -y
pip3 install fastapi uvicorn websockets sqlalchemy
```

### 6.5 下载 Win11 桌面软件

| 软件 | 用途 | 下载地址 |
|------|------|---------|
| Sideloadly | iOS IPA 签名 | https://sideloadly.io |
| Rufus | 制作越狱 U 盘 | https://rufus.ie |
| Node.js (LTS) | 运行 open-lovable | https://nodejs.org |
| pnpm | 包管理器 | `npm install -g pnpm` |

### ✅ 阶段一验收

```
[ ] WSL2 + Ubuntu 正常运行
[ ] VS Code 能连接 WSL
[ ] Python3 + pip3 已安装
[ ] 云服务器 SSH 可连接
[ ] Sideloadly / Rufus / Node.js / pnpm 已下载安装
```

---

## 7. 阶段二：iPhone 8 越狱 & 纯净包提取（第2天）

> ⏱ 预计耗时：3-5 小时
> 🚨 **最容易翻车的阶段！请严格按步骤操作**

### 7.1 ⚠️ 越狱前必须做

```
□ 拔出国内 SIM 卡
□ 设置 → 通用 → 语言改为 English
□ 时区改为目标国家（如 New York）
□ 关闭定位服务
□ 如果有密码 → 先关掉

然后：
设置 → 通用 → 传输或还原 iPhone → 抹掉所有内容和设置

⚠️ 重新激活时：
   ❌ 不要设锁屏密码
   ❌ 不要录 Touch ID
   ❌ 不要登录 Apple ID
   ❌ 不要设屏幕使用时间密码
```

### 7.2 制作越狱 U 盘 & 越狱

```bash
# 1. 下载 palen1x 镜像
# https://github.com/palera1n/palen1x/releases

# 2. 用 Rufus 写入 U 盘（选 DD 模式！）

# 3. 重启 → F12 选 U 盘启动 → 进 palen1x 界面
# 4. 选 palera1n → Rootless
# 5. 按提示让手机进 DFU 模式：
#    音量+ → 音量- → 长按电源10秒 → 电源+音量-5秒
# 6. 等待自动完成 → 手机重启

# 7. 手机桌面出现 palera1n 图标 → ✅ 越狱成功
```

### 7.3 安装砸壳工具 & 提取 TikTok IPA

```
1. 打开 palera1n → Install Sileo
2. 打开 Sileo → 搜索安装 TrollDecryptor
3. App Store 下载 TikTok
4. 打开 TrollDecryptor → 点击 TikTok → 砸壳
5. 导出 TikTok.ipa → 传回 Win11 电脑

✅ 拿到一个纯净的解密版 TikTok 安装包（200MB+）
```

### 7.4 还原手机

```
重启手机 → 越狱状态消失 → 回到普通模式
现在可以设密码、登录 Apple ID 了
```

### ✅ 阶段二验收

```
[ ] palen1x U 盘已制作
[ ] iPhone 8 成功越狱
[ ] TikTok.ipa 纯净包已提取（200MB+）
[ ] IPA 已传回 Win11
```

---

## 8. 阶段三：🔥 用 open-lovable 构建 XNOW 云控网站（第3-4天）

> ⏱ 预计耗时：2 天
> ⭐ **这是整个系统的门面，最重要的一步**
> 🎨 **记得套用第5章的 XNOW 品牌配色方案**

### 8.1 关于 firecrawl/open-lovable

**它是什么？**
- 一个开源项目，让你通过 AI 聊天来构建 React 应用
- 可以输入一个 URL，它自动克隆成 React 项目
- 内置 Firecrawl 抓取 + AI 生成代码

**我们用他来做什么？**
```
输入 wsyufu.net 的界面风格 + 功能描述
      ↓
AI 生成一个完整的 TK 云控管理后台 React 项目
      ↓
我们修改 API 地址 → 指向自己的 FastAPI 后端
      ↓
部署到服务器 → 成为我们的云控网站
```

### 8.2 安装 open-lovable

```bash
# 在 WSL 或 Win11 终端中执行

# 克隆项目
git clone https://github.com/firecrawl/open-lovable.git
cd open-lovable

# 安装依赖
pnpm install

# 创建环境变量文件 .env.local
# 至少需要 FIRECRAWL_API_KEY + 一个 LLM 的 API Key
```

**.env.local 内容：**

```env
# 必填
FIRECRAWL_API_KEY=你申请的firecrawl_key

# AI 提供商（四选一）
GEMINI_API_KEY=你的gemini_key    # ★ 推荐，免费

# 沙箱（使用 Vercel 默认即可）
SANDBOX_PROVIDER=vercel
```

### 8.3 启动 open-lovable

```bash
pnpm dev
# 打开 http://localhost:3000
```

你会看到一个聊天界面。这就是你的"AI 前端工程师"。

### 8.4 🎯 让 AI 生成 XNOW 云控网站

在 open-lovable 的聊天框里，输入下面的指令（一次不用全说，可以分步）：

**第一轮对话：**（基础框架 + 登录页 + XNOW 品牌）

```
请帮我创建一个 TikTok 云控管理后台的 React 应用。

品牌名称：XNOW（中文：XNOW 云控）
参考设计风格：https://wsyufu.net
品牌色：紫蓝渐变 #667eea → #764ba2，深色背景 #1a1a2e，#16213e，#0f3460

需要包含以下页面和功能：

【页面 0：登录页】（最重要，未登录时显示这个）
- 品牌 Logo "XNOW" 显示在页面中央上方，使用紫蓝渐变文字
- 背景使用深色渐变（#1a1a2e → #16213e → #0f3460）
- 用户名输入框 + 密码输入框
- "登录"按钮（紫蓝渐变背景）
- 登录成功后跳转到数据概览页
- 登录失败显示红色错误提示

【页面 1：数据概览】 - 登录后的首页
- 顶部统计卡片：设备总数、在线设备、今日任务、执行成功率
- 在线设备列表表格

【页面 2：设备管理】
- 表格：设备编号、机器码、分组、在线状态、运行状态、今日任务、操作按钮
- 每个设备有【下发任务】【编辑】【删除】按钮
- ⚠️ 删除按钮点击后弹出确认对话框
- 顶部搜索框、状态筛选下拉框
- 分页

【页面 3：批量任务】
- 任务类型卡片网格：批量关注、批量私信、评论点赞、发布作品等
- 点击卡片弹出任务创建表单
- 已创建任务列表表格
- 分页

【页面 4：账号管理】
- 表格：TKUID、昵称、TK号、状态、粉丝数、健康分、地区
- 筛选栏：状态、设备、标签、国家地区
- 批量导入按钮

【页面 5：素材管理】
- Tab 切换：素材文件 / 文字模板
- 上传素材按钮
- 素材列表表格

【全局要求】
1. 左侧深色侧边栏（#16213e），品牌名 "XNOW" 用渐变文字
2. 所有按钮使用紫蓝渐变背景
3. 页面数据加载时显示 Loading 动画（品牌紫色旋转图标）
4. 数据为空时显示"暂无数据"的空状态提示（带图标）
5. 网络错误时显示错误提示和"重新加载"按钮
6. 所有删除操作有二次确认弹窗
7. 所有操作成功/失败有 Toast 提示
8. 先用模拟数据展示，后续切换为真实 API
```

**第二轮对话（等第一轮生成完后）：**

```
请继续添加以下页面：

1. 【批量任务】页面：
   - 用卡片网格展示任务类型：批量关注、批量私信、评论点赞、取消关注、发布作品、用户采集、自动上号、养号
   - 每张卡片有图标、名称和描述
   - 点击卡片弹出创建任务的表单对话框
   - 下方有已创建任务列表：表格显示任务名称、类型、目标设备、调度、优先级、启用状态

2. 【账号管理】页面：
   - 表格：TKUID、昵称、TK号、状态（正常/风控/掉登录）、粉丝数、健康分、地区、操作
   - 顶部筛选栏：账号状态、设备、标签、国家地区

3. 【素材管理】页面：
   - Tab 切换：素材文件 / 文字模板
   - 上传按钮
   - 素材列表：文件名、类型、使用次数、状态、上传时间
```

**第三轮对话（优化）：**

```
请优化整个应用的样式：
1. 左侧导航改为深色背景，当前菜单项高亮
2. 表格行 hover 有浅色背景效果
3. 按钮有圆角和过渡动画
4. 统计卡片有毛玻璃效果或阴影
5. 整体配色参考 TikTok 的品牌色（黑色 + 粉色/红色点缀）
6. 响应式设计，在手机和电脑上都能看
7. 添加页面之间的过渡动画
```

### 8.5 连接 open-lovable 生成的前端到我们的后端

open-lovable 生成的项目中，API 调用部分需要改成指向你的 FastAPI 后端。

**新建 API 配置文件** `src/api/config.ts`：

```typescript
// API 基础配置
const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://你的服务器IP:8000';

export const api = {
  // 设备相关
  async getDevices() {
    const res = await fetch(`${API_BASE_URL}/api/devices`);
    return res.json();
  },

  // 发送指令
  async sendAction(deviceId: string, action: string) {
    const res = await fetch(`${API_BASE_URL}/api/action/${deviceId}/${action}`, {
      method: 'POST',
    });
    return res.json();
  },

  // 获取统计数据
  async getStats() {
    const res = await fetch(`${API_BASE_URL}/api/stats`);
    return res.json();
  },

  // 获取任务列表
  async getTasks(page = 1) {
    const res = await fetch(`${API_BASE_URL}/api/tasks?page=${page}`);
    return res.json();
  },

  // 创建任务
  async createTask(task: any) {
    const res = await fetch(`${API_BASE_URL}/api/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task),
    });
    return res.json();
  },

  // WebSocket 状态（用于实时更新）
  wsBaseUrl: process.env.NEXT_PUBLIC_WS_URL || `ws://你的服务器IP:8000`,
};
```

把项目中所有写死的模拟数据替换为调用 `api.xxx()` 函数。

> 💡 **如果觉得手动改麻烦**：直接在 open-lovable 的聊天框里说：
> "请把项目中所有的模拟数据调用改为 API 调用，API 基础地址为 http://服务器IP:8000，帮我创建一个 api/config.ts 文件"

### 8.6 部署前端网站

**方法 A：部署到 Vercel（最简单，推荐）**

```bash
# 1. 安装 Vercel CLI
npm install -g vercel

# 2. 在项目目录执行
vercel

# 3. 按提示登录 → 关联 Git 仓库 → 部署
# 4. 部署成功后得到一个 https://xxx.vercel.app 域名
```

**方法 B：部署到自己的云服务器**

```bash
# 1. 构建生产版本
npm run build

# 2. 把构建产物传到服务器
scp -r out/* root@服务器IP:/var/www/tkcloud/

# 3. 配置 Nginx
sudo cat > /etc/nginx/sites-available/tkcloud-frontend << 'EOF'
server {
    listen 80;
    server_name 你的域名;
    root /var/www/tkcloud;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # API 反向代理到 FastAPI 后端
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
    }

    # WebSocket 代理
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
```

### 8.7 网站最终效果

```
在浏览器打开 https://你的域名

你看到的是：
┌──────────────────────────────────────────────────────┐
│  TK云控  │  📊 数据概览  📋 批量任务  ⏰ 定时任务   │
│  ─────── │  📈 执行统计  📝 任务日志  📱 设备管理   │
│          │  👤 账号管理  🎬 素材管理                │
│  品牌logo │  ════════════════════════════════════   │
│          │  在线设备: 1 台    今日任务: 23 次       │
│          │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐   │
│          │  │ 设备  │ │ 在线  │ │ 今日  │ │ 成功  │   │
│          │  │ 总数  │ │ 设备  │ │ 任务  │ │ 率   │   │
│          │  │  5   │ │  1   │ │  23  │ │ 95%  │   │
│          │  └──────┘ └──────┘ └──────┘ └──────┘   │
│          │                                         │
│          │  📱 在线设备列表                          │
│          │  ┌────┬──────┬────┬────┬────┬────┬────┐ │
│          │  │  # │ 设备 │状态│运行│今日│账号│操作 │ │
│          │  ├────┼──────┼────┼────┼────┼────┼────┤ │
│          │  │  1 │ i8_1 │在线│空闲│ 12 │ @tk│下滑 │ │
│          │  └────┴──────┴────┴────┴────┴────┴────┘ │
│          │                                         │
└──────────────────────────────────────────────────────┘
```

### ✅ 阶段三验收

```
[ ] open-lovable 已安装并可以运行
[ ] AI 生成的数据概览页面完整
[ ] AI 生成的设备管理页面完整
[ ] AI 生成的批量任务页面完整
[ ] AI 生成的账号管理页面完整
[ ] AI 生成的素材管理页面完整
[ ] API 配置已指向自己的服务器地址
[ ] 网站已部署（Vercel 或云服务器）
[ ] 在浏览器能正常打开访问
[ ] 所有页面有模拟数据展示
```

---

## 9. 阶段四：云服务器后端 API 开发 + 安全认证（第5-6天）

> ⏱ 预计耗时：2 天
> ⭐ **前端页面需要的所有数据，都由这个后端提供**

### 9.1 后端项目结构

```
/root/tk_cloud_backend/
├── main.py              # 程序入口 + FastAPI 实例
├── config.py            # 配置文件
├── database.py          # 数据库连接
├── models.py            # 数据表模型
├── schemas.py           # API 数据格式定义
├── routers/
│   ├── __init__.py
│   ├── devices.py       # 设备管理 API
│   ├── tasks.py         # 任务管理 API
│   ├── accounts.py      # 账号管理 API
│   ├── stats.py         # 统计 API
│   └── ws.py            # WebSocket 连接管理
├── services/
│   ├── device_manager.py    # 设备管理逻辑
│   └── task_runner.py       # 任务执行逻辑
├── requirements.txt
└── .env
```

### 9.2 🎯 给 AI 的 Prompt（后端代码 + JWT 认证）

在 VS Code 中连接云服务器（Remote SSH），创建 `/root/tk_cloud_backend/` 目录，然后执行：

```bash
# 先建好目录
mkdir -p /root/tk_cloud_backend/routers /root/tk_cloud_backend/services
```

然后对 AI 说（分步进行）：

**第0步 — 先加 JWT 认证（必须先做！）：**

```
请帮我添加完整的用户认证系统到 FastAPI 项目。

需要：

1. config.py 添加：
   - SECRET_KEY = 随机字符串（从 .env 读取）
   - ALGORITHM = "HS256"
   - ACCESS_TOKEN_EXPIRE_MINUTES = 1440（24小时）

2. 添加 auth.py：
   - 用户模型 User：id, username, password_hash, role(admin/operator), is_active, created_at
   - 密码使用 passlib 的 bcrypt 加密
   - create_access_token(data) -> JWT token
   - verify_token(token) -> 解码验证
   - get_current_user 依赖注入（从请求头 Authorization: Bearer xxx 读取）

3. 添加 routers/auth.py：
   - POST /api/auth/login → 用户名密码登录，返回 access_token
   - POST /api/auth/register → 创建新用户（仅管理员可调）
   - GET /api/auth/me → 获取当前用户信息
   - PUT /api/auth/change-password → 修改密码

4. 在 routers 目录添加 deps.py：
   - get_current_active_user 依赖（验证 token + 检查用户是否激活）
   - 所有需要登录的 API 都加上这个依赖

5. 启动时创建默认管理员账号：admin / admin123

6. WebSocket 也要支持 token 验证（通过 URL 参数传 token）
```

**第1步 — main.py + 数据库：**

```
请帮我创建一个 Python FastAPI 后端项目，这是 TikTok 云控系统的服务器端。

技术栈：FastAPI + SQLAlchemy + SQLite（后续可切换 PostgreSQL）

请生成以下文件：

1. config.py：
   - 从 .env 读取配置
   - DATABASE_URL（默认 sqlite:///./tkcloud.db）
   - WS_PORT（默认 8000）
   - API_KEY（用于前端调用鉴权）

2. database.py：
   - SQLAlchemy 连接配置
   - SessionLocal 依赖注入

3. models.py（数据库表模型）：
   - Device 表：id, device_id(唯一), name, group_name, status(online/offline), running_status(idle/running/locked), today_tasks(int), machine_code, app_version, created_at, last_seen
   - Account 表：id, device_id(外键), tk_uid, nickname, tk_number, avatar, status(normal/risk/logged_out), followers(int), fans_today(int), health_score(int), region, tags, two_fa(bool), created_at, updated_at
   - Task 表：id, task_type, name, device_id(目标设备), priority(int), enabled(bool), schedule_type(once/recurring), cron_expr, status(pending/running/completed/failed), progress(int), source, created_at, next_run
   - TaskLog 表：id, task_id(外键), device_id, action, status, message, created_at
   - Media 表：id, filename, file_type(video/image/text), file_url, group_name, use_count, status, created_at

4. schemas.py：
   - 每个模型的 Pydantic 请求/响应 Schema

请生成完整可运行的代码。
```

**第2步 — API 路由：**

```
请继续为 FastAPI 项目创建以下路由文件：

1. routers/devices.py：
   - GET /api/devices → 获取所有设备列表（支持分页、搜索、筛选）
   - GET /api/devices/{device_id} → 获取单个设备详情
   - POST /api/devices → 手动添加设备
   - PUT /api/devices/{device_id} → 更新设备信息（名称、分组等）
   - DELETE /api/devices/{device_id} → 删除设备
   - POST /api/device/action/{device_id}/{action} → 向设备发送指令
   - POST /api/device/broadcast/{action} → 向所有设备群发指令

2. routers/tasks.py：
   - GET /api/tasks → 任务列表（分页、按类型/状态筛选）
   - POST /api/tasks → 创建新任务
   - PUT /api/tasks/{id} → 更新任务
   - DELETE /api/tasks/{id} → 删除任务
   - POST /api/tasks/{id}/enable → 启用/禁用任务

3. routers/accounts.py：
   - GET /api/accounts → 账号列表（分页、筛选）
   - POST /api/accounts → 添加账号
   - PUT /api/accounts/{id} → 更新账号信息
   - DELETE /api/accounts/{id} → 删除账号
   - POST /api/accounts/{id}/bind → 绑定到设备
   - POST /api/accounts/batch-import → 批量导入账号（CSV）

4. routers/stats.py：
   - GET /api/stats/overview → 总览统计（设备总数/在线/任务数/成功率）
   - GET /api/stats/daily → 每日统计（近7/30天趋势）
   - GET /api/stats/tasks → 各任务类型统计

5. routers/ws.py：
   - WebSocket /ws/{device_id} → 设备连接管理
   - 心跳检测（30秒超时）
   - 消息广播
   - 自动重连支持
```

**第3步 — main.py 主入口：**

```
请帮我写 main.py 主入口文件，把上面所有的路由注册进去，并包含：
1. CORS 中间件（允许前端跨域访问）
2. 启动时自动创建数据库表
3. 静态文件服务（用于前端构建产物）
4. 根路由 / 返回 API 状态信息
5. 完整的异常处理

要求最终能通过 python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 直接启动。
```

### 9.3 部署后端

```bash
# 1. 安装依赖
cd /root/tk_cloud_backend
pip3 install -r requirements.txt

# 2. 测试启动
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
# 看到 Application startup complete → 成功

# 3. 测试 API
curl http://127.0.0.1:8000/api/stats/overview

# 4. 配置 systemd 持久运行
sudo cat > /etc/systemd/system/tkcloud.service << 'EOF'
[Unit]
Description=TK Cloud Backend
After=network.target

[Service]
User=root
WorkingDirectory=/root/tk_cloud_backend
ExecStart=/usr/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tkcloud
sudo systemctl start tkcloud
sudo systemctl status tkcloud
```

### 9.4 云服务器安全组配置

```
登录云服务器控制台 → 安全组/防火墙 → 添加入站规则：

┌──────────┬──────┬──────────┬────────────┐
│ 方向     │ 协议 │ 端口     │ 来源       │
├──────────┼──────┼──────────┼────────────┤
│ 入方向   │ TCP  │ 8000     │ 0.0.0.0/0  │
│ 入方向   │ TCP  │ 80       │ 0.0.0.0/0  │
│ 入方向   │ TCP  │ 443      │ 0.0.0.0/0  │
└──────────┴──────┴──────────┴────────────┘
```

### ✅ 阶段四验收

```
[ ] 所有数据库表已创建（SQLite 文件存在）
[ ] GET /api/devices 返回设备列表
[ ] GET /api/stats/overview 返回统计数据
[ ] POST /api/tasks 可以创建任务
[ ] WebSocket /ws/test 可以连接
[ ] systemd 服务正常运行
[ ] 从外网能访问到 API
```

---

## 10. 阶段五：iOS 注入插件（Tweak）开发（第7-9天）

### 10.1 WSL 中安装 Theos

```bash
# 在 WSL Ubuntu 中
export THEOS=/opt/theos
sudo git clone --recursive https://github.com/theos/theos.git $THEOS
sudo mkdir -p $THEOS/sdks

# 下载 iOS 16.5 SDK
sudo curl -L https://github.com/theos/sdks/releases/latest/download/iPhoneOS16.5.sdk.tar.xz -o /tmp/sdk.tar.xz
sudo tar -xf /tmp/sdk.tar.xz -C $THEOS/sdks/
sudo chown -R $(whoami) $THEOS

# 验证
$THEOS/bin/nic.pl
# 看到 "NIC 2.0" → 成功（按 Ctrl+C 退出）
```

### 10.2 创建 Tweak 项目

```bash
cd ~
$THEOS/bin/nic.pl
# 选 [1] tweak
# Project Name: TKCloudPlugin
# Package Name: com.yourname.tkcloud
# Author: yourname
# Bundle Identifier: com.zhiliaoapp.musically (TikTok 包名)
# Install Method: rootless

cd TKCloudPlugin
```

### 10.3 🎯 AI Prompt — 插件代码

**Tweak.x 核心代码：**

```
我正在用 Theos 开发注入 TikTok 的 iOS 插件，实现多环境隔离云控。
请用 Objective-C / Logos 语法写完整的 Tweak.x 代码：

【核心功能 1：多环境数据沙箱（最重要）】
- 修改 TikTok 的数据存储路径，实现多环境隔离
- 默认路径：/Documents/com.zhiliaoapp.musically/
- 改为：/Documents/environments/env_{环境ID}/com.zhiliaoapp.musically/
- 每个环境拥有完全独立的：
  □ NSUserDefaults（偏好设置互不干扰）
  □ Cookies / WKWebsiteDataStore（登录态隔离）
  □ NSFileManager 数据目录（缓存不交叉）
  □ Keychain 服务（账号密码不共享）
- 通过服务端下发的 current_env 字段切换当前激活的环境
- 切换环境时保存旧环境状态，加载新环境数据
- 返回 {"type":"register","device":"设备ID","env_count":当前环境数}

【核心功能 2：WebSocket 连接】
- 使用 NSURLSessionWebSocketTask（原生，不需第三方库）
- 连接地址：ws://你的服务器IP:8000/ws/手机设备ID
- 断线自动重连（3秒间隔）
- 发送注册消息携带设备信息

【核心功能 3：指令处理】
收到 JSON 解析 action 字段，支持：
1. "scroll_down" → 模拟屏幕下滑手势翻页
2. "scroll_up" → 上滑返回
3. "like" → 点击点赞按钮位置
4. "follow" → 点击关注按钮
5. "comment" → 在评论框输入预设文本
6. "switch_env" → 切换到指定环境（从当前环境保存状态，加载新环境）
7. "create_env" → 创建新环境（新建数据沙箱目录）
8. "delete_env" → 删除指定环境
9. "login_account" → 打开登录页，填入账号密码并登录
10. "logout" → 退出当前环境登录的账号
11. "check_status" → 返回当前环境和账号状态

【UI 指示器】
- 右上角显示半透明小圆点（直径20px）
- 绿色=已连接 / 红色=断开 / 黄色=切换环境中
- 点击小圆点弹出菜单显示：当前环境ID、账号状态、环境总数
- 小圆点可拖动位置

【代码混淆】
- 所有类名和方法名前缀用随机字符串（如 "xz_"）
- 不要输出敏感关键词到 NSLog
- 环境目录名用 base64 编码防止明文扫描
- 不要输出敏感关键词到日志
- 不要修改 TikTok 原始功能
```

### 10.4 修改 Makefile

```
请在 Tweak 项目的 Makefile 中设置：
- ARCHS = arm64（iPhone 8 架构）
- TARGET = iphone:16.5:14.0
- 输出文件名改为 TKCloudPlugin.dylib（不要叫 tweak.dylib）
- 添加 -O2 优化标志
- 开启 strip 去掉符号表
```

### 10.5 编译

```bash
make package
# 成功 → 生成 .theos/obj/debug/TKCloudPlugin.dylib
# 报错 → 复制错误给 AI 修复
```

### ✅ 阶段五验收

```
[ ] Theos 安装正常
[ ] Tweak 项目创建成功
[ ] AI 生成了完整的 Tweak.x 代码
[ ] 编译成功，生成 TKCloudPlugin.dylib（100KB+）
```

---

## 11. 阶段六：打包、签名 & 安装（第10天）

### 11.1 购买签名证书

```
淘宝搜 "iOS UDID 个人开发者证书"
提供 iPhone 8 的 UDID → 商家发给你：
□ P12 证书文件
□ .mobileprovision 描述文件
□ 证书密码
```

### 11.2 Sideloadly 注入 + 签名

```
1. Win11 打开 Sideloadly
2. USB 连接 iPhone 8
3. 拖入 TikTok.ipa（阶段二提取的）
4. 点 Advanced Options → Inject Dylib/Framework
5. 选择 TKCloudPlugin.dylib（阶段五编译的）
6. 选择淘宝买的证书（P12 + mobileprovision）
7. 点 Start → 自动注入 + 签名 + 安装
8. 手机出现 TikTok 图标 → ✅ 成功
```

### 11.3 安装后配置

```
1. 拔掉数据线
2. 设置 → 通用 → VPN与设备管理 → 信任证书
3. 手机连软路由 Wi-Fi（必须走海外代理）
4. 插上海外过期物理 SIM 卡
5. 关闭 App Store 自动更新
6. 关闭自动锁屏（永不锁屏）
```

### ✅ 阶段六验收

```
[ ] 证书已购买
[ ] IPA + dylib 注入签名成功
[ ] 手机已安装魔改版 TikTok
[ ] 手机已信任证书
[ ] 网络环境已配置（软路由 + 海外IP + SIM卡）
```

---

## 12. 阶段七：前后端联调 + 功能全量扩展（第11-15天）

### 12.1 第一步：联调打通（第11天）

**操作流程：**

```
1️⃣ 云服务器启动后端
   sudo systemctl start tkcloud

2️⃣ 手机打开魔改版 TikTok
   → 服务器日志显示：[设备上线] iPhone_8_001 连入

3️⃣ 浏览器打开前端网站
   → 数据概览页显示：设备在线数 1

4️⃣ 点击【一键下滑】按钮
   → 手机 TikTok 自动翻页 ✅

5️⃣ 测试所有指令
   □ 下滑翻页
   □ 点赞
   □ 关注
   □ 评论
```

配置完整的 Nginx（前端 + 后端 + WebSocket 统一入口）：

```nginx
server {
    listen 80;
    server_name 你的域名或IP;

    # 前端静态文件
    root /var/www/tkcloud;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # API 代理到 FastAPI
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # WebSocket 代理
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
    }

    # 静态资源缓存
    location /_next/ {
        proxy_pass http://127.0.0.1:3000;
        expires 365d;
    }
}
```

### 12.2 第二步：扩展完整任务系统（第12天）

在 open-lovable 的聊天框中对 AI 说：

```
请在我的云控后台项目中增加完整的任务创建和执行功能：

1. 在"批量任务"页面增加创建任务对话框：
   - 任务类型选择（下拉框）：批量关注/批量私信/评论点赞/取消关注/发布作品/用户采集/自动上号/自动切号/创建环境/删除环境/养号
   - 目标设备选择（多选）
   - 任务参数配置（不同任务类型不同参数）
   - 优先级设置
   - 调度方式：立即执行 / 定时执行

2. 增加"定时任务"页面：
   - 新建定时计划
   - CRON 表达式输入
   - 循环间隔设置
   - 已创建计划列表

3. 为每个任务类型创建对应的表单字段：
   - 批量关注：输入目标用户名（支持批量）
   - 批量私信：选择用户 + 私信内容模板
   - 发布作品：选择素材视频 + 标题 + 标签
   - 养号：选择时长、行为模式（随机/侧重互动/侧重发布）
   - **自动上号**：从账号仓库选择账号 → 下发到指定手机 → 插件自动打开TK登录页 → 填入账号密码 → 点击登录 → 返回登录结果
   - **批量上号**：批量选择账号 → 排队依次登录（间隔2分钟防风控）→ 显示登录成功/失败状态
   - **账号检测**：登录后自动检测账号状态（正常/风控/掉登录）→ 更新后台状态

请生成完整的 React 组件代码。
```

### 12.3 第三步：视频去重系统（第12天）

```bash
# 在云服务器上安装 FFmpeg
ssh root@服务器IP
apt install ffmpeg -y
```

给 AI 的 Prompt：

```
请用 Python 写一个视频批量去重工具：

1. 输入目录 /input，输出目录 /output
2. 对每个 .mp4 文件执行 FFmpeg 操作：
   - 随机调整亮度：-5% 到 +5%
   - 随机调整对比度：-3% 到 +3%
   - 随机裁剪 1-2 像素边缘
   - 随机调整音频采样率（±0.5%）
   - 修改文件创建时间元数据
3. 输出文件名：原文件名_dedup_序号.mp4
4. 多线程处理（同时处理 4 个文件）
5. 显示处理进度条
```

### 12.4 第四步：完整账号管理（第13天）

在 open-lovable 中对 AI 说：

```
请在我的云控后台增加完整的账号管理功能：

1. 【账号列表】页面：
   - 表格列：头像、TKUID、昵称、TK号、状态（正常/风控/掉登录）、粉丝、今日涨粉、健康分、地区、标签、最后更新、操作
   - 顶部筛选：状态、设备、标签、国家地区、2FA状态
   - 搜索框：搜索TKUID/昵称/TK号

2. 【账号仓库】（Account Pool）页面：
   - 这是所有账号的中央存储池
   - 表格：账号ID、用户名、密码、状态（池中/已分配/回收中）、所属设备、国家、标签
   - 批量导入：CSV上传、手动添加
   - 分配到设备：选择账号→选择目标设备→分配
   - 自动分配：系统自动从池中分配账号到空闲设备
   - 回收：从设备回收账号回池中
   - 批量导出

3. 【账号登录】页面：
   - 管理登录凭据（账号密码）
   - 显示每个账号的登录状态（成功/失败/重试中）
   - 失败原因显示
   - 支持批量重试
   - 登录模式选择

4. 【环境管理】（每个设备的环境）：
   - 显示每台设备上的环境列表（环境ID、状态、绑定账号）
   - 创建新环境
   - 删除环境
   - 查看环境详情

5. 账号详情弹窗：
   - 显示完整账号信息
   - 关联的环境和设备
   - 操作记录
   - 健康分变化趋势图

6. 账号状态监控：
   - 自动检测账号是否掉登录
   - 健康分低于阈值自动暂停
   - 自动补充账号（池中空闲低于N个时预警）
```

### 12.5 第五步：数据统计与日志（第14天）

```
请为我的云控后台增加数据统计和日志功能：

1. 执行统计页面：
   - 统计概览卡片：总任务数、成功率、失败率、执行中
   - 每日趋势折线图（近7天/30天）
   - 各任务类型分布饼图
   - 设备活跃度排名

2. 任务日志页面：
   - 表格：时间、设备、任务类型、操作内容、状态、详情
   - 筛选：按设备、任务类型、时间范围、状态
   - 日志详情弹窗
   - 导出日志（CSV）

使用 Chart.js 或 Recharts 做图表。
```

### 12.6 最终整体联调（第15天）

**全功能测试清单：**

```
□ 数据概览页面显示正确的统计数据
□ 设备管理页面：增删改查设备正常
□ 下发指令到单台设备正常执行
□ 群发指令到所有设备正常执行
□ 批量关注任务能创建和执行
□ 批量私信任务能创建和执行
□ 发布作品任务能上传视频并发布
□ 定时任务准时触发
□ 养号任务模拟真人行为
□ 账号管理页面显示正确的账号信息
□ 素材管理能上传和管理文件
□ 执行统计显示正确的图表数据
□ 任务日志能检索和导出
□ WebSocket 断线重连正常
□ 多台手机同时在线正常
□ 品牌名称和 Logo 已替换为你自己的
```

### ✅ 阶段七验收

```
[ ] 前端页面所有数据来自真实后端
[ ] 14 种任务类型均可正常执行
[ ] 定时任务系统工作正常
[ ] 账号管理系统完整可用
[ ] 素材管理系统完整可用
[ ] 数据统计图表正确
[ ] 日志系统完整可检索
[ ] FFmpeg 视频去重脚本正常
[ ] 全功能测试全部通过
```

---

## 13. 阶段八：🔐 安全加固 + HTTPS + 多设备扩容（第16-18天）

> ⏱ 预计耗时：3 天
> ⭐ **把系统从"能跑"升级为"能生产用"**

### 13.1 HTTPS/SSL 证书配置

**为什么必须 HTTPS？**
- WebSocket 在 HTTPS 页面中只能用 WSS（加密 WebSocket）
- 浏览器会拦截 HTTP 页面发起的 WS 连接（混合内容错误）
- 登录密码明文传输不安全

**使用 Let's Encrypt 免费证书：**

```bash
# 1. 在云服务器上安装 certbot
ssh root@服务器IP
apt install certbot python3-certbot-nginx -y

# 2. 配置 Nginx 先获取证书
# 先确认域名已解析到服务器IP
# 然后：
certbot --nginx -d 你的域名.com

# 3. 按照提示输入邮箱，同意协议
# 证书自动配置到 Nginx，有效期90天

# 4. 证书自动续期
certbot renew --dry-run
# 没问题的话 certbot 会自动加定时任务续期
```

**Nginx 完整配置（HTTPS + WebSocket）：**

```nginx
server {
    listen 443 ssl http2;
    server_name 你的域名.com;

    ssl_certificate /etc/letsencrypt/live/你的域名.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/你的域名.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 前端静态文件
    root /var/www/xnow;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # API 代理到后端
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket 代理（必须！）
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
    }

    # 静态资源缓存
    location /static/ {
        expires 365d;
        add_header Cache-Control "public, immutable";
    }
}

# HTTP → HTTPS 跳转
server {
    listen 80;
    server_name 你的域名.com;
    return 301 https://$server_name$request_uri;
}
```

### 13.2 Docker 容器化部署

**为什么用 Docker？**
- 一键部署，不用再手动配环境
- 本地开发和服务器环境一致
- 迁移服务器只需一条命令

**Dockerfile（后端）：**

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**docker-compose.yml（完整部署）：**

```yaml
version: '3.8'

services:
  backend:
    build: ./backend
    ports:
      - "8000:8000"
    volumes:
      - ./backend:/app
      - ./data:/app/data  # SQLite 数据持久化
    environment:
      - SECRET_KEY=${SECRET_KEY}
      - DATABASE_URL=sqlite:///./data/tkcloud.db
    restart: always

  frontend:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./frontend-dist:/usr/share/nginx/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
      - ./ssl:/etc/letsencrypt
    depends_on:
      - backend
    restart: always
```

### 13.3 多设备扩容方案

**从 1 台 iPhone 扩到多台：**

| 设备数 | 需要什么 | 预算增加 |
|:------:|---------|:--------:|
| 1-5 台 | 工业级 USB HUB（带独立供电）+ 数据线 | ~¥300 |
| 5-20 台 | 增加 USB HUB + 手机散热架 + 机架 | ~¥1000 |
| 20+ 台 | 专用群控机柜 + 独立供电系统 | ~¥5000+ |

**多设备管理要点：**

```
1. 每台手机分配唯一 device_id：iPhone_001, iPhone_002 ...

2. 每台手机独立海外 IP（软路由 MAC 绑定）
   - 软路由上为每个 MAC 分配不同 IP
   - 一号一 IP，绝对不能共用

3. USB HUB 连接架构：
   [电脑] → [USB HUB 1] → iPhone_001
                         → iPhone_002
                         → iPhone_003
           → [USB HUB 2] → iPhone_004
                         → iPhone_005

4. 多设备同时签名
   - Sideloadly 支持同时连多台设备
   - 统一制作好 IPA，用同一个证书签所有设备
   - 注意：个人开发者证书最多绑 100 台设备

5. 手机统一管理
   - 所有手机刷同一个系统版本
   - 所有手机装同一个魔改 IPA
   - 在后台"设备管理"页面统一监控
```

### 13.4 数据库备份与恢复

**自动备份脚本：**

```bash
#!/bin/bash
# backup.sh - 每天凌晨自动备份

BACKUP_DIR="/root/backups"
DB_PATH="/root/tk_cloud_backend/tkcloud.db"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 备份数据库
cp $DB_PATH "$BACKUP_DIR/tkcloud_$DATE.db"

# 备份上传的文件（视频素材等）
tar -czf "$BACKUP_DIR/uploads_$DATE.tar.gz" /root/tk_cloud_backend/uploads

# 保留最近 7 天的备份，删除更早的
find $BACKUP_DIR -name "tkcloud_*.db" -mtime +7 -delete
find $BACKUP_DIR -name "uploads_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

**配置定时备份：**

```bash
# 安装到系统定时任务
chmod +x /root/backup.sh
crontab -e

# 添加以下行（每天凌晨3点备份）
0 3 * * * /root/backup.sh >> /var/log/backup.log 2>&1
```

**恢复方法：**

```bash
# 停止服务
systemctl stop tkcloud

# 恢复数据库
cp /root/backups/tkcloud_20260623_030000.db /root/tk_cloud_backend/tkcloud.db

# 恢复上传文件
tar -xzf /root/backups/uploads_20260623_030000.tar.gz -C /root/tk_cloud_backend/

# 重启服务
systemctl start tkcloud
```

---

## 14. 阶段九：运维与监控告警（第19-20天）

> ⏱ 预计耗时：2 天
> **让系统 7x24 小时稳定运行**

### 14.1 设备离线告警

**后端添加告警逻辑（给 AI 的 Prompt）：**

```
请为 FastAPI 后端添加设备离线告警功能：

1. 如果设备超过 5 分钟没有心跳（WebSocket 断开且未重连）
2. 记录告警到数据库 alert_logs 表
3. 支持以下通知方式：
   a. 网页端弹窗提示（SSE 推送）
   b. Server酱/企业微信机器人 Webhook 通知
4. API 端点：
   - GET /api/alerts → 获取告警列表
   - POST /api/alerts/config → 配置通知方式
   - PUT /api/alerts/{id}/ack → 确认告警
```

### 14.2 服务健康监控

```bash
# 简单健康检查脚本 - monitor.sh
#!/bin/bash

SERVICE_URL="https://你的域名.com/api/stats/overview"
TOKEN="你的管理员token"

# 检查后端是否在线
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" $SERVICE_URL)

if [ $HTTP_CODE != "200" ]; then
    echo "❌ 后端服务异常! HTTP: $HTTP_CODE"
    # 尝试重启
    systemctl restart tkcloud
    echo "重启完成，发送通知..."
    # 这里可以调用 Server酱 发送微信通知
    curl -s "https://sctapi.ftqq.com/你的SendKey.send?title=XNOW云控-服务异常&desp=后端返回$HTTP_CODE，已自动重启"
else
    echo "✅ 服务正常"
fi
```

```bash
# 每5分钟检查一次
*/5 * * * * /root/monitor.sh >> /var/log/monitor.log 2>&1
```

### 14.3 前端性能优化

| 优化项 | 方法 | 效果 |
|--------|------|------|
| 静态资源缓存 | Nginx 配置 expires + Cache-Control | 减少重复加载 |
| 数据懒加载 | 分页+滚动加载 | 大数据量不卡 |
| WebSocket 心跳 | 30秒心跳维持连接 | 不断连 |
| API 响应缓存 | redis 缓存统计结果 | 减少数据库查询 |
| 前端代码分包 | React.lazy + Suspense | 首屏加载更快 |

### 14.4 服务器资源监控

```bash
# 安装监控工具
apt install htop iotop net-tools -y

# 查看资源使用
htop                    # CPU/内存
df -h                   # 磁盘空间
free -h                 # 内存
netstat -tlnp          # 端口监听
```

**长期运行建议：**
- 云服务器最低配置：2核4G，40G SSD
- 每月重启一次服务器清理内存
- 磁盘使用率超过 80% 自动告警
- 定期检查 Nginx 日志是否有异常访问

### ✅ 阶段八+九验收

```
[ ] HTTPS 证书已配置，网站通过 https:// 访问
[ ] HTTP 自动跳转到 HTTPS
[ ] WebSocket 通过 WSS 正常连接
[ ] Docker 部署脚本可一键启动
[ ] 数据库自动备份每天执行
[ ] 多台手机同时在线测试通过
[ ] 设备离线告警正常触发
[ ] 服务健康检查脚本正常运行
[ ] 前端页面加载速度优化（<3秒）
[ ] 服务器资源监控已配置
```

## 15. AI 提示词大全

### 15.1 open-lovable 克隆网站（阶段三用）

```
请帮我创建一个 TikTok 云控管理后台的 React 应用。
参考这个网站的设计风格：https://wsyufu.net
需要包含以下页面：数据概览、设备管理、批量任务、定时任务、账号管理、素材管理、执行统计、任务日志。
先使用模拟数据展示。
```

### 15.2 后端 main.py（阶段四用）

```
请帮我创建一个完整的 Python FastAPI 后端项目，包含 SQLAlchemy 数据库模型、
设备管理/任务管理/账号管理/统计/WebSocket 等完整 API 路由。
技术栈：FastAPI + SQLAlchemy + SQLite。
需要完整的可运行代码。
```

### 15.3 iOS Tweak 插件 + 环境隔离（阶段五用）

```
我正在用 Theos 开发注入 TikTok 的 iOS 插件，需要多环境隔离支持。
请用 Objective-C 写 Tweak.x：

1. 多环境数据沙箱：
   - 修改 TikTok 数据目录为 /Documents/environments/env_{ID}/
   - 每个环境独立：NSUserDefaults、Cookies、FileManager、Keychain

2. WebSocket 连接服务器，注册时携带设备信息和环境数

3. 指令处理：scroll_down/like/follow/comment/switch_env/create_env/delete_env/login_account/logout

4. UI 连接状态指示器（绿/红/黄三色）

5. 断线自动重连、代码混淆
```

### 15.4 JWT 用户认证系统（阶段四用）

```
请在 FastAPI 项目中添加用户认证系统：
1. 用户模型 User（id, username, password_hash, role, is_active）
2. 密码 bcrypt 加密，登录返回 JWT token
3. 所有 API 加上 get_current_user 依赖
4. WebSocket 通过 URL 参数验证 token
5. 默认管理员账号 admin/admin123
```

### 15.5 HTTPS + Docker 部署（阶段八用）

```
请帮写 Dockerfile 和 docker-compose.yml：
1. 后端 Python FastAPI 容器
2. 前端 Nginx 容器（含 SSL 配置）
3. 数据卷持久化 SQLite
4. 自动重启策略
5. 环境变量通过 .env 传入
```

### 15.6 设备离线告警（阶段九用）

```
请为 FastAPI 后端添加设备离线告警：
1. 设备 5 分钟无心跳触发告警
2. 告警表：alert_logs
3. Server酱/企业微信 Webhook 通知
4. SSE 推送让前端弹窗
5. 告警确认 API
```

### 15.7 通用报错修复

```
我在 [描述你做的步骤] 时报错：
[粘贴完整错误信息]
我是小白看不懂，请直接告诉我怎么修复。
```

---

## 16. 成本核算

### 一次性投入

| 项目 | 预算（¥） |
|------|-----------|
| U 盘 | ~20 |
| 数据线 | ~30 |
| 海外 SIM 卡 | ~10 |
| 苹果证书 | 30-100 |
| **总计** | **约 ¥100-160** |

### 月度运营

| 项目 | 月费（¥）|
|------|----------|
| 云服务器 | 50-100（已有则0）|
| 海外住宅 IP | 30-60/个 |
| AI API | 按量（已有则0）|
| **总计（1台）** | **¥80-160** |

---

## 17. 🚨 特级警告与避坑指南

### 🔴 红色警告

| # | 警告 | 后果 |
|---|------|------|
| 1 | 越狱后绝对不能设锁屏密码 | 无限重启白苹果 |
| 2 | 魔改 TikTok 绝对不能直连国内网络 | 账号永久小黑屋 |
| 3 | Dylib 文件名不能叫 tweak/hack/cheat | 被检测封设备 |
| 4 | 没有环境隔离直接切换账号 | 设备指纹交叉导致批量封号 |
| 5 | 批量发视频必须 FFmpeg 去重改 MD5 | 全部限流封号 |

### 🟡 黄色警告

| # | 警告 | 说明 |
|---|------|------|
| 5 | 云服务器安全组必须放行端口 | 否则打不开网站 |
| 6 | 免费 Apple ID 7天过期需重签 | 建议买证书 |
| 7 | 小火箭替代软路由需配规则 | 否则 WebSocket 走代理会断连 |
| 8 | TikTok 版本更新可能让插件失效 | 关闭自动更新 |
| 9 | 手机长时间运行注意散热 | 加散热背夹 |

---

## 18. 故障排查手册

### 网站打不开（http://服务器IP:8000）

```
检查顺序：
1. 云服务器安全组是否放行 8000 端口
2. systemctl status tkcloud 服务是否运行
3. curl http://127.0.0.1:8000 本地是否能访问
4. 云服务器防火墙：ufw status
```

### 前端页面显示但设备列表为空

```
1. 手机是否打开魔改版 TikTok
2. 手机是否连了软路由 Wi-Fi
3. 服务器日志 journalctl -u tkcloud -f 是否显示设备连入
4. 手机端右上角小圆点是绿色还是红色
```

### 其他常见问题

| 问题 | 解决方法 |
|------|---------|
| palera1n 提示不在 DFU 模式 | 换 USB-A to Lightning 原装线 |
| 编译报错 | 完整复制错误给 AI 修复 |
| Sideloadly 不识别手机 | 安装 iTunes（包含驱动）|
| 安装后闪退 | dylib 注入错误或 TikTok 版本不匹配 |
| 账号 0 播放 | 检查 whoer.net 伪装度 |

---

## 附录 A：完整 API 端点清单（参考系统逆向结果）

> 从 wsyufu.net JS 源码中提取的全部 API 路由，用于构建后端时对照。

### 认证与用户
```
POST   /api/auth/login          # 登录，返回 JWT token
POST   /api/auth/register       # 注册（仅管理员）
GET    /api/auth/me             # 当前用户信息
PUT    /api/auth/change-password # 修改密码
```

### 设备管理
```
GET    /biz/v2/devices/                     # 设备列表（分页+搜索+筛选）
PATCH  /biz/v2/devices/{id}/                # 更新设备
PATCH  /biz/v2/devices/{id}/tags/           # 更新设备标签
POST   /biz/v2/devices/batch-delete/        # 批量删除
POST   /biz/v2/devices/batch-offline/       # 批量设为离线
GET    /biz/v2/devices/online-stats/         # 在线统计
GET    /biz/v2/device-bindings/             # 设备绑定列表
PATCH  /biz/v2/device-bindings/{id}/        # 更新绑定
GET    /biz/v2/device-groups/               # 设备分组列表
POST   /biz/v2/device-groups/               # 创建分组
PATCH  /biz/v2/device-groups/{id}/          # 更新分组
DELETE /biz/v2/device-groups/{id}/          # 删除分组
```

### 账号管理（核心）
```
GET    /biz/v2/account-passcodes/               # 账号凭据列表
POST   /biz/v2/account-passcodes/               # 添加凭据
PATCH  /biz/v2/account-passcodes/{id}/          # 更新凭据
DELETE /biz/v2/account-passcodes/{id}/          # 删除凭据
POST   /biz/v2/account-passcodes/batch-login-status/  # 批量登录状态
POST   /biz/v2/account-passcodes/import/        # 批量导入
POST   /biz/v2/account-passcodes/import-csv/    # CSV导入
GET    /biz/v2/account-passcodes/export/        # 导出
POST   /biz/v2/account-passcodes/clear-all/     # 清空全部

GET    /biz/v2/account-pool/                    # 账号仓库列表
POST   /biz/v2/account-pool/import/             # 导入到仓库
GET    /biz/v2/account-pool/export/             # 从仓库导出
GET    /biz/v2/account-pool/stats/              # 仓库统计
POST   /biz/v2/account-pool/auto-assign/        # 自动分配到设备
POST   /biz/v2/account-pool/batch-assign/       # 批量分配到设备
POST   /biz/v2/account-pool/batch-recycle/      # 批量回收
POST   /biz/v2/account-pool/batch-invalidate/   # 批量标记无效
POST   /biz/v2/account-pool/batch-status/       # 批量更新状态
POST   /biz/v2/account-pool/batch-delete/       # 批量删除
PATCH  /biz/v2/account-pool/{id}/tags/          # 更新标签
PATCH  /biz/v2/account-pool/{id}/credentials/   # 更新凭据

GET    /biz/v2/accounts/                        # 账号列表
GET    /biz/v2/accounts/stats/                  # 账号统计
GET    /biz/v2/accounts/{id}/health-detail/     # 健康分详情
PATCH  /biz/v2/accounts/{id}/tags/              # 更新账号标签

GET    /biz/v2/country-options/                 # 国家/地区选项
```

### 任务管理
```
GET    /biz/v2/tasks/                           # 任务列表
POST   /biz/v2/tasks/                           # 创建任务
DELETE /biz/v2/tasks/{id}/                      # 删除任务
POST   /biz/v2/tasks/batch/create/              # 批量创建
POST   /biz/v2/tasks/force-release/             # 强制释放
GET    /biz/v2/task-schemas/                    # 任务模式
GET    /biz/v2/task-templates/                  # 任务模板
GET    /biz/v2/task-executions/                 # 执行记录
GET    /biz/v2/account-execution-stats/         # 账号执行统计
```

### 定时任务
```
GET    /biz/v2/schedules/                       # 定时计划列表
POST   /biz/v2/schedules/                       # 创建定时计划
PATCH  /biz/v2/schedules/{id}/                  # 更新
DELETE /biz/v2/schedules/{id}/                  # 删除
```

### 素材管理
```
GET    /biz/v2/materials/                       # 素材列表
POST   /biz/v2/materials/                       # 上传素材
DELETE /biz/v2/materials/{id}/                  # 删除
POST   /biz/v2/materials/batch-delete/          # 批量删除
GET    /biz/v2/materials/list-for-select/       # 选择列表
GET    /biz/v2/material-groups/                 # 素材分组
POST   /biz/v2/material-groups/                 # 建分组
GET    /biz/v2/material-groups/tree/            # 分组树
GET    /biz/v2/text-templates/                  # 文字模板
POST   /biz/v2/text-templates/                  # 新建模板
DELETE /biz/v2/text-templates/{id}/             # 删除
POST   /biz/v2/text-templates/batch-delete/     # 批量删除
POST   /biz/v2/text-templates/batch-import/     # 批量导入
POST   /biz/v2/upload/image/                    # 上传图片
GET    /biz/v2/oss/presign/                     # OSS预签名URL
```

### 采集数据
```
GET    /biz/v2/user-targets/                    # 采集用户列表
POST   /biz/v2/user-targets/import/             # 导入
POST   /biz/v2/user-targets/clear/              # 清空
POST   /biz/v2/user-targets/clear-group/        # 清空分组
POST   /biz/v2/user-targets/move-to-group/      # 移动分组
POST   /biz/v2/user-targets/batch-tag/          # 批量打标
POST   /biz/v2/user-targets/batch-status/       # 批量更新状态
GET    /biz/v2/user-targets/stats/              # 统计
POST   /biz/v2/user-targets/export-delete/      # 导出删除
GET    /biz/v2/user-targets/groups/             # 用户分组
GET    /biz/v2/collected-videos/                # 采集的视频
POST   /biz/v2/collected-videos/clear/          # 清空视频
POST   /biz/v2/collected-videos/clear-group/    # 清空分组
POST   /biz/v2/collected-videos/move-to-group/  # 移动分组
GET    /biz/v2/collected-comments/              # 采集的评论
POST   /biz/v2/collected-comments/clear/        # 清空评论
POST   /biz/v2/collected-comments/clear-group/  # 清空分组
POST   /biz/v2/collected-comments/move-to-group/ # 移动分组
POST   /biz/v2/collected-content/batch-tag/     # 批量打标
GET    /biz/v2/data/comments-export/            # 评论导出
```

### 回复配置
```
GET    /biz/v2/follow-reply/                    # 关注回复
POST   /biz/v2/follow-reply/                    # 新建
PATCH  /biz/v2/follow-reply/{id}/               # 更新
DELETE /biz/v2/follow-reply/{id}/               # 删除
GET    /biz/v2/keyword-reply/                   # 关键词回复
POST   /biz/v2/keyword-reply/                   # 新建
PATCH  /biz/v2/keyword-reply/{id}/              # 更新
DELETE /biz/v2/keyword-reply/{id}/              # 删除
GET    /biz/v2/comment-groups/                  # 评论分组
GET    /biz/v2/link-templates/                  # 链接模板
```

### App版本管理
```
GET    /biz/v2/app-versions/                    # 版本列表
POST   /biz/v2/app-versions/                    # 上传新版本
PATCH  /biz/v2/app-versions/{id}/               # 更新
DELETE /biz/v2/app-versions/{id}/               # 删除
GET    /biz/v2/app-version/latest/              # 最新版本
```

### 公告与反馈
```
GET    /biz/v2/announcements/                   # 公告列表
POST   /biz/v2/announcements/                   # 发布公告
PATCH  /biz/v2/announcements/{id}/              # 更新
DELETE /biz/v2/announcements/{id}/              # 删除
GET    /biz/v2/feedback/                        # 反馈列表
PATCH  /biz/v2/feedback/{id}/                   # 回复
```

### 系统设置
```
GET    /biz/v2/automation-rules/                # 自动化规则
POST   /biz/v2/automation-rules/                # 保存规则
GET    /biz/v2/client-config/                   # 客户端配置
PATCH  /biz/v2/client-config/                   # 更新配置
```

### 卡密/许可证系统（商业版核心）
```
GET    /biz/v2/my/licenses/                     # 我的卡密
POST   /biz/v2/my/licenses/note/                # 设置备注
GET    /biz/v2/my-clients/                      # 我的客户
GET    /biz/v2/agent/dashboard/                 # 代理看板
GET    /biz/v2/agent/config/                    # 代理配置
GET    /biz/v2/agent/license-keys/              # 代理卡密列表
POST   /biz/v2/agent/licenses/distribute/       # 分发卡密
POST   /biz/v2/agent/licenses/recall/           # 回收卡密
GET    /biz/v2/agent/licenses/                  # 代理许可证
POST   /biz/v2/agent/notes/set/                 # 设置备注
GET    /biz/v2/agent/tags/                      # 代理标签
POST   /biz/v2/agent/tags/set/                  # 设置标签
POST   /biz/v2/agent/tags/remove/               # 删除标签
GET    /biz/v2/agent/users/                     # 代理的下级用户
POST   /biz/v2/agent/users/create/              # 创建下级用户

# 管理员
GET    /biz/v2/admin/users                      # 用户管理
GET    /biz/v2/admin/agents/                    # 代理管理
GET    /biz/v2/admin/agent-config/              # 代理配置
GET    /biz/v2/admin/license-groups/            # 卡密分组
GET    /biz/v2/admin/license-keys/              # 卡密管理
POST   /biz/v2/admin/license-keys/import/       # 导入卡密
POST   /biz/v2/admin/license-keys/allocate/     # 分配卡密
POST   /biz/v2/admin/license-keys/recall/       # 回收卡密
POST   /biz/v2/admin/license-keys/delete/       # 删除卡密
GET    /biz/v2/admin/license-keys/stats/        # 卡密统计
GET    /biz/v2/admin/license-keys/import-logs/  # 导入日志

GET    /biz/v2/roles                            # 角色管理
GET    /biz/v2/audit/param-export/              # 审计导出
```

### 统计看板
```
GET    /biz/v2/dashboard/stats/                 # 看板统计数据
GET    /biz/v2/account-execution-stats/         # 账号执行统计
```

---

## 附录 B：完整页面功能规格（对标验收清单）

> 以下清单对照 wsyufu.net 的每个页面，逐项列出功能点。

### 📊 数据概览（Dashboard）
```
□ 统计卡片：设备总数、在线数、空闲数、执行中数、离线数
□ 今日执行次数汇总
□ 在线设备列表（表格）
□ 账号状态分布概览
□ 快速操作按钮
□ 刷新按钮
□ 时间范围选择
```

### 📋 批量任务（Task Management）
```
□ 创建任务对话框（按类型分）
  互动类：
    □ 批量关注（输入目标用户名，支持批量）
    □ 批量私信（选择用户 + 私信内容模板）
    □ 评论点赞（对视频进行点赞评论）
    □ 取消关注（批量取关目标用户）
    □ 指定视频评论
    □ 批量视频评论
  发布类：
    □ 发布作品（视频/图文，支持批量）
    □ 隐藏全部视频
  采集类：
    □ 用户采集（采集目标用户信息）
    □ 采集视频评论
    □ 采集博主视频
    □ 本地采集点赞
    □ 本地采集关注
    □ 性别筛选
  账号类：
    □ 修改账号资料（批量修改头像/简介）
    □ 自动上号（自动登录账号到设备）
    □ 自动切号（切换设备当前账号）
    □ 重新登录
    □ 退出登录
    □ 开启2FA
    □ 移除历史设备
  养号/系统：
    □ 养号（模拟真人浏览行为）
    □ 更新安装包（下发APK更新）

□ 任务列表表格：任务类型 | 名称 | 目标设备 | 调度 | 优先级 | 启用 | 来源 | 进度 | 创建时间 | 下次执行 | 操作
□ 筛选：全部/互动/发布/采集/账号/养号 + 状态 + 人工 + 搜索
□ 统计卡片：总任务、已启用、已停用、循环任务
□ 每行操作：编辑/删除/启用禁用
```

### ⏰ 定时任务
```
□ 全部/定时/循环 Tabs
□ 新建计划按钮
□ 表格：ID | 名称 | 类型 | 调度方式 | 计划时间 | 循环间隔 | 目标设备 | 启用 | 操作
□ 搜索任务名称
□ 支持 cron 表达式
```

### 📊 执行统计
```
□ 统计概览：总执行次数、成功、失败、平均成功率
□ 日期范围选择（开始/结束）
□ 搜索账号
□ 账号执行明细表格：账号 | 统计日期 | 总执行 | 成功 | 失败 | 成功率
```

### 📝 任务日志
```
□ 筛选：设备ID/任务ID/账号ID + 状态 + 日期范围
□ 表格：执行ID | 任务 | 设备 | 执行账号 | 状态 | 开始时间 | 结束时间 | 耗时 | 错误信息 | 操作
□ 分页
```

### 📱 设备管理
```
□ Tabs：设备列表 / 分组管理
□ 统计卡片：设备总数、空闲、执行中、锁定、离线
□ 搜索：设备编号/机器码
□ 筛选：全部状态/全部分组/App版本
□ 按钮：批量修改分组、批量删除、下发任务
□ 表格：序号 | 手机编号 | 设备机器码 | 分组 | 在线状态 | 运行状态 | 今日任务 | 绑定账号 | 标签 | App版本 | 操作
□ 每行操作：下发 | 编辑 | 删除
□ 分页（20条/页）

  分组管理子页：
  □ 表格：ID | 分组名称 | 设备数 | 在线 | 说明 | 状态 | 操作
  □ 新建分组
  □ 批量删除
```

### 👤 账号管理
```
□ Tabs：账号列表 / 账号仓库 / 账号登录

  账号列表：
  □ 表格：账号信息(头像+TKUID+昵称+TK号) | 状态(正常/风控/掉登录) | 安全信息 | 设备 | 粉丝 | 今日涨粉 | 健康分 | 地区 | 标签 | 更新时间 | 操作
  □ 筛选：状态/设备/标签/国家/2FA状态
  □ 搜索：TKUID/昵称/TK号
  □ 操作：详情/回收
  □ 分页

  账号仓库：
  □ 表格：账号ID/用户名/密码/状态/所属设备/国家/标签
  □ 批量导入（CSV）
  □ 导出
  □ 自动分配/批量分配/批量回收
  □ 统计概览

  账号登录：
  □ 表格：TKUID | 登录账号 | 登录密码 | 登录方式 | 登录模式 | 国家 | 上号状态 | 失败原因 | 设备编号 | 有效 | 标签 | 更新时间 | 操作
  □ 搜索+筛选：上号状态/登录模式/国家/TKUID/标签
  □ 批量导入 | CSV导入 | 导出 | 清空全部 | 新增密码记录
  □ 操作：重试/编辑/删除
```

### 🎬 素材管理
```
□ Tabs：素材文件 / 文字模板
□ 统计：素材文件数、文字模板数、使用统计
□ 分组树
□ 上传素材 / 批量上传
□ 搜索文件名
□ 类型筛选
□ 表格：文件名 | 类型 | 使用次数 | 状态 | 创建时间 | 操作
□ 文字模板子页：新建/编辑/删除/批量导入
```

### 📊 采集数据
```
□ Tabs：用户数据 / 视频数据 / 评论数据
□ 表格：昵称 | 数据 | 地区 | 性别 | 来源 | 进度 | 标签 | 层级 | 入库时间 | 操作
□ 分组筛选
□ 批量打标
□ 导出
```

### 📢 公告中心
```
□ 公告列表
□ 发布公告
□ 编辑/删除
```

### 💬 反馈中心
```
□ 反馈列表
□ 回复反馈
```

### ⚙️ 回复配置
```
□ Tabs：关注回复 / 私信自动回复 / 打码配置
□ 回复规则表格
□ 新增规则
□ 编辑/删除
□ 链接模板管理
□ 评论分组
```

### 🔧 设置中心
```
□ 账号信息：用户名/API ID/邮箱/加入时间
□ 修改密码
□ 数据入库过滤规则：最低粉丝数/最高关注数/允许入库地区
□ 数据保留策略：热→温/温→冷 自动降级
□ 自动化规则：
  □ 自动暂停风险账号（健康分低于X分时 / 24h连续失败X次标记风控）
  □ 自动补充账号（使用中低于X个时 / 仓库空闲低于X个时预警）
□ 采集设置：性别筛选开关
□ 我的卡密：卡密列表/刷新
```

### 📖 使用教程
```
□ 教程目录：
  1. 安装小火箭 Shadowrocket
  2. 购买独享 VPN 节点
  3. 查询设备 UDID
  4. 安装 App（签名版）
  5. 安装 App（巨魔版）
  6. 激活绑定后台
  7. 你的第一个任务
```

### 🔐 卡密/分销系统（商业版）
```
  □ 我的卡密列表
  □ 卡密激活
  □ 代理看板（统计）
  □ 代理配置
  □ 下级用户管理
  □ 卡密分发/回收
  □ 备注/标签管理
  □ 管理员后台：用户管理/代理管理/卡密管理/角色管理
```

---

## 附录 C：数据表完整设计

```sql
-- 核心业务表
devices              -- 设备表
  id, device_id, name, machine_code, group_id, app_version,
  status(online/offline/running/locked), running_status(idle/running),
  today_tasks, tags, last_seen, created_at

device_groups        -- 设备分组
  id, name, description, status, device_count, online_count

device_bindings      -- 设备绑定关系
  id, device_id, account_pool_id, env_id, status, created_at

account_passcodes    -- 账号凭据（登录用）
  id, tk_uid, username, password, login_method, login_mode,
  country, login_status, fail_reason, device_id, is_valid, tags

account_pool         -- 账号仓库
  id, tk_uid, nickname, tk_number, avatar, status(pool/assigned/recycled),
  device_id, followers, fans_today, health_score, region, tags,
  credentials, last_used, created_at

accounts             -- 账号信息（运行时）
  id, pool_id, device_id, env_id, status(normal/risk/logged_out),
  followers, fans_today, health_score, region, tags,
  last_check, updated_at

tasks                -- 任务表
  id, pro_task(任务类型), name, description, device_ids,
  priority, enabled, schedule_type(once/recurring), cron_expr,
  status, progress, source, created_at, next_run

task_executions      -- 任务执行记录
  id, task_id, device_id, account_id, status, started_at,
  finished_at, duration, error_message

schedules            -- 定时计划
  id, name, task_type, schedule_type, cron_expr, interval,
  target_devices, enabled, created_at

materials            -- 素材文件
  id, filename, file_type(video/image), file_url, thumb_url,
  group_id, use_count, status, file_size, created_at

text_templates       -- 文字模板
  id, title, content, type(comment/dm), group_id, use_count, created_at

material_groups      -- 素材分组
  id, name, parent_id, sort_order

user_targets         -- 采集的用户数据
  id, nickname, tk_uid, region, gender, source, progress,
  tags, level, collected_at, group_id

collected_videos     -- 采集的视频
  id, video_id, author, title, url, collected_at, group_id

collected_comments   -- 采集的评论
  id, comment_id, author, content, video_id, collected_at, group_id

announcements        -- 公告
  id, title, content, priority, status, created_at

feedback             -- 反馈
  id, user_id, content, reply, status, created_at

follow_reply         -- 关注自动回复
  id, keyword, reply_type(text/image), content, status

keyword_reply        -- 关键词自动回复
  id, keyword, reply_type, content, match_type(exact/fuzzy), status

automation_rules     -- 自动化规则
  id, rule_type, config(JSON), enabled, created_at

app_versions         -- App版本管理
  id, version, platform, file_url, release_notes, status, created_at

-- 商业/分销表
licenses             -- 卡密
  id, key, group_id, status, assigned_to, assigned_at,
  expires_at, notes, created_at

license_groups       -- 卡密分组
  id, name, description, config(JSON)

agents               -- 代理
  id, user_id, parent_id, commission_rate, level, status

agent_users          -- 代理下级用户
  id, agent_id, user_id, status, created_at

roles                -- 角色/权限
  id, name, permissions(JSON), created_at

audit_logs           -- 审计日志
  id, user_id, action, target_type, target_id, detail, ip, created_at

-- 系统表
users                -- 系统用户
  id, username, password_hash, role, is_active, api_key, created_at

client_config        -- 客户端配置
  id, config_key, config_value(JSON), updated_at
```

---

> 📌 **本文档涵盖范围**：完整逆向分析 wsyufu.net 参考后台，提取了 100+ API 端点、18+ 页面、40+ 数据表、20+ 任务类型、卡密分销体系。
> 
> 📌 **对照这个清单开发，确保不遗漏任何一个商业级功能。**
