# 行动方案：纯网络层交互打通（阶段一技术验证）

> 2026-08-30 参谋模式收敛 | 祥哥确认的五条支柱 + 验证边界
> 目的：用纯网络层打通 四件套(点赞/关注/评论/改资料) + 自动浏览养号，每个 100% 真成功，设备全程不崩不掉线。

## 一、决策前提（祥哥拍板）

| # | 支柱 | 含义 |
|---|------|------|
| 1 | 交付客户的产品 | 稳、有兜底、客户能上手 |
| 2 | 客户自己用面板 | 后台是交付物（阶段三做） |
| 3 | 坚定走网络层 | 触摸层废弃，不回头 |
| 4 | 100% 真成功 | 服务器读回验证，绝不误报假成功 |
| 5 | 钉死 TikTok 43.7.0 | 逆向签名 / 深度适配长期有效（版本不会自己升级打破） |

**验证边界**：四件套 + 养号全通 = 阶段一通过，进入功能铺开。

## 二、核心架构问题

纯网络层需要两样东西，缺一不可：

1. **会话材料**（Cookie / device_id / x-tt-token + **签名**）
   - 现状：NSURLProtocol 两个拦截器在这台设备**从未拦到任何 TikTok 请求**（四路证据：piggyback=0、accounts 表空、collect_videos=0、headers=0）
   - 登录态 333 keys 完整 → 不是没会话，是**拦不到**
2. **读回通道**（digg 后拉状态验证 `is_digg`，follow 后验证 `is_following`）

## 三、阶段一步骤

### Step 1 — 设备端探针（v1.4.136）：解开"TikTok 网络走哪条路"之谜

这是当前唯一卡点，必须最先解。

**新增 `net_diag` 命令**，一次返回：
- `[NSURLProtocol registeredClassNames]` 是否含 XNURLProtocol / XNOWURLProtocol（**注册是否成功**）
- 两个拦截器各自**命中计数**（canInitWithRequest 里 ++）+ 最近判定的 URL
- **NSURLSession hook** 命中计数 + 最近 URL（swizzle `dataTaskWithRequest:` 及 completionHandler 变体）
- `gLastFeedHeaders` / `gLastFeedURL` 状态
- `_cachedVideos` 数

**新增 `net_sniff <秒>` 命令**：N 秒内记录所有观察到的请求 host+URL（不管哪层），摸清 TikTok 实际网络路径。

**判定 → 三路线**：

| net_diag 结果 | 结论 | 路线 |
|--------------|------|------|
| NSURLSession hook 命中 feed 请求 | TikTok 走 NSURLSession | **路线C：直接复用 headers → net_like 打通（最轻）** |
| NSURLSession 有命中但无 feed | 部分走系统栈 | 路线B：借力 TikTok 网络类 |
| 两者都 0 | 完全绕过系统网络层 | 路线B：定位 TikTok 自研网络入口 |

### Step 2 — 按路线打通会话材料

- **路线C（最轻）**：hook 到 feed 请求 → headers 缓存到 `gLastFeedHeaders` → 复用构造 digg/follow/comment 请求
- **路线B（借力，钉死版本可长期有效）**：定位 TikTok 发起请求的代码路径（swizzle 其网络类 / hook NSURLSession 底层），在 TikTok 自己发请求时**复制完整请求（含签名）**供复用
- **路线A（重型备选，最后才上）**：逆向 X-SS-STUB / x-arg / x-ladon 签名算法，完全脱离 app 运行时构造请求。成本周级，但最可控

### Step 3 — 四件套网络层化（统一模式）

每个交互统一骨架：

```
复用会话材料构造请求 → 下发 → 读回状态 → 真成功才报 success
→ 失败重试 N 次 → 仍失败标记"需人工"，绝不误报
```

| 交互 | 端点（已知） | 读回验证 |
|------|------------|---------|
| 点赞 | `/aweme/v1/aweme/digg/` POST | 拉该视频 `is_digg=true` |
| 关注 | `/aweme/v1/aweme/follow/` POST | `is_following=true` |
| 评论 | `/aweme/v1/comment/publish/` POST | 评论存在于该视频评论列表 |
| 改资料 | `/aweme/v1/user/update/` POST | 拉资料字段已变化 |

### Step 4 — 自动浏览养号

- 纯网络层拉 feed（复用会话材料）→ 定时浏览：拉一条 → 停留 → 可选的 like 行为
- 每次行为读回验证，全程有日志

## 四、每步验收证据（证据先行，缺项不交）

| 步骤 | 验收证据 |
|------|---------|
| Step1 探针 | `net_diag` 返回注册状态/命中计数/最近 URL，据此判定路线 |
| Step2 材料 | 构造请求复用 headers，非空且含 Cookie/device_id/x-tt-token |
| like | digg 下发 → 读回 `is_digg=true`；前后端日志可审计 |
| follow | 读回 `is_following=true` |
| comment | 读回评论存在于评论列表 |
| edit_profile | 读回资料字段已变化 |
| 养号 | 连续 N 小时设备不掉线、无崩溃、行为有日志 |
| **四件套+养号全通** | 四件套各 ≥10 次连续真成功 + 养号 ≥4h 稳定 + `regression-check.py all` 全绿 |

## 五、风险预案

| 风险 | 预案 |
|------|------|
| 签名被拒(403) | 路线B 借力不依赖签名，直接兜底 |
| TikTok 网络层定位失败 | 路线A 逆向签名兜底（钉死版本可行） |
| 读回通道也走不通 | ui_scan 界面控件读回兜底（最后手段，触摸验证不可靠） |
| 设备崩溃/掉线 | 装机前先跑 `regression-check.py all`；崩溃自愈兜底 |
| 客户场景(阶段三) | 架构预留"面板下发任务 → 设备网络层执行 → 读回"接口，面板不阻塞阶段一 |

## 六、工作量估算

| 项 | 估算 |
|----|------|
| Step1 探针(v1.4.136) | 1 次构建+装机 |
| 路线C 打通 | net_like 收尾 + 3 个新命令，各 ~1 天 |
| 路线B 借力定位 | 1-3 天逆向 |
| 路线A 签名逆向 | 1-2 周（最后手段） |
| 养号 | 2-3 天 |
| 读回验证框架 | 1 天 |

## 七、与后续衔接

- 阶段二（功能铺开）：批量关注/取关、发布/私信/直播——同构复用四件套骨架
- 阶段三（产品化）：面板客户化、多设备编排、任务下发、监控告警、装机自动化
- 架构上所有交互走同一"会话材料 + 读回验证"抽象，功能铺开 = 填端点
