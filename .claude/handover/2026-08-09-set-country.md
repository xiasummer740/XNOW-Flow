# 接力开发笔记：2026-08-09 设备端环境伪装 set_country（切换国家核心）

> 交接：PPT 全功能计划第一批第3项，按祥哥方向调整为"设备端环境伪装优先"
> 关联：PLAN 文档 · 决策1(切换国家=A方案加速器+校验) 落地的设备端部分

## 📌 完成状态

| 项 | 状态 |
|---|---|
| 功能 | **set_country/get_country 环境伪装**（把 region/时区/语言/MCC 伪装成目标国） |
| 版本 | commit `8acfbb0`，v1.4.53 IPA 构建成功（374MB），**上传 VPS 中待装机** |
| CI | ✅ Actions 编译成功（CountryEnv.m 已进 dylib） |
| 真机测试 | ⏳ 待祥哥装 v1.4.53 验证 |

## 🎯 交付内容

**CountryEnv.h/.m**（新增）：
- 30国映射表：国家中文名 → {region, tz, tz_offset, lang, mcc_mnc}
  （美国/日本/英国/韩国/新加坡/台港澳/德法/东南亚/俄乌/印巴/中东/非洲等）
- `setCountry:` 写入 NSUserDefaults `XN_CountryEnv`
- `applyEnvToMutableRequest:` 改写请求 query 参数（只改已存在参数，保守不新增）

**XNURLProtocol.m**：`startLoading` 转发前调用 `[CountryEnv applyEnvToMutableRequest:forwardReq]`，改写：
`device_region / app_region / sys_region / region / tz_name / timezone_offset / app_language / sys_language / language / mcc_mnc / carrier_region`

**CommandEngine**：新增 `set_country`(params.country) / `get_country` 命令，后端可直接远程下发

**XNFloatingPanel**：浮窗"设置国家"点选即生效（写入本地环境伪装）

## 🔑 关键技术结论（务必传给祥哥）

1. **IP 是权威，伪装是加固**：TikTok 服务端按出口 IP GeoIP 定账号区；改客户端参数是"辅助一致性"，IP 中国+参数美国=不一致=风控。
2. **出口 IP 由用户小火箭（Shadowrocket）海外节点提供**，我们不建节点。
   - ⚠️ 小火箭要开**全局/TUN 模式**（或确保 TikTok 命中代理规则），否则 TikTok 流量不走海外 = IP 没变。
3. **只改已存在的 query 参数**（保守防抖）；**不拦截注册请求**（tiktokv.com 全量拦截曾崩，避免再踩）。
4. 需要真机抓包确认当前版本实际参数名（不同版本 device_region vs app_region 不同），现按公共知识实现，真机验证后微调。

## ⚠️ 待真机验证清单（装 v1.4.53 后）

1. `set_country` 命令下发"美国" → get_country 回读 env
2. 抓包看 feed 请求 query 里 device_region=US / tz_name=America/New_York / mcc_mnc=310410
3. 小火箭开全局/TUN + 选美国节点 → 后端 GeoIP 看设备出口=美国
4. 注册流程：美国出口 + 环境一致 → 账号美区

## 📦 保留台账（暂不扩展）

- 后端 ProxyNode 节点台账 + GeoIP + device.country 门禁（commit a0b7cba）——祥哥走小火箭方案后不是重点，代码保留后续用
- device.last_ip 已在 ws.py 轮询记录（GeoIP 识别设备出口国家的基础）

## 🛠 下一步

- v1.4.53 装机验证 set_country（依赖祥哥设备 + 小火箭）
- 第一批第4项：后端 /api/translate
- 第二批：其余设备命令 + 浮窗补丁A
