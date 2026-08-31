# TODO 快照 — 2026-08-31（新对话接力点）

## 当前进度（纯网络层 Step 0 网络路径探针，咽喉环节）
1. **✅ v1.4.137 装机复测**：installHooks 根因修复确认生效（session.hits 0→10，抓到第三方 SDK 流量）
2. **⚠️ 决定性发现**：祥哥滑 TikTok 期间 net_diag 结果零变化，TikTok 主 API **0 条**走 NSURLSession → 疑似走自研 C++ 网络栈（路线 B）
3. **✅ v1.4.138 决定性探针已构建 + 已上传**（四项能力：registered 读取修复 / global_asked 全局计数 / swizzle 扩 dataTaskWithURL+uploadTask / net_sniff 时间盒命令）
4. **⏳ 待祥哥装机 138 → 下发 net_sniff 10 + net_diag 一锤定音判路线**

## 下一步（按顺序）
1. **祥哥装机 138** → 我下发 `net_sniff 10`（祥哥滑 TikTok）+ `net_diag` → server.log 读结果（`.tmp-poll-netdiag.py`）
2. **判路线**（判定表在 docs/action-plan-pure-network-layer.md:42-48）：
   - session 命中 tiktokv/byteoversea → 路线 C（复用 headers，最轻）
   - global_asked>0 但 TikTok 域 asked=0 → 路线 B（借力 TikTok 自研网络类）
   - global_asked=0 → 注册失败，先修注册
3. **路线 B 起点**：内省 MusicallyCore 找请求模型（RepostDiggRequestModel 已确认）→ 借力发请求复制完整 headers
4. **Step 1 四件套**（like/follow/comment/edit 网络层真执行）→ Step 2 评论区采集 → 后续（docs/action-plan-traffic-loop.md）

## 关键产物位置
- 138 IPA：`http://192.129.210.52/TikTok_XNOW_v1.4.138_BH.ipa`（本地 TikTok_XNOW_v1.4.138_BH.ipa）
- dylib：build-artifacts-ci/xnower-138/xnower.dylib
- 打包脚本：build-vps-dylib-138.py + .tmp-inject-138.py（以 static 最新已注入 IPA 作 base）
- 查结果：.tmp-poll-netdiag.py（ssh tail server.log）

## 风险备忘
- 前端"执行结果"区不一定回显 → 直接 ssh tail server.log 拿（`Device ... result: {...}` 行）
- VPS 无 43.7.0 原始包 → 连续注入，base 链靠 static 最新版
- 字节系 App 用自研网络栈（业界已知），大概率路线 B，别抱路线 C 幻想
- 设备空闲会崩（TikTok 自身 bug + 低内存），导航/采集多留恢复手段
