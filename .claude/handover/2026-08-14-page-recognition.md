# 2026-08-14 手机当前页实时识别（6页）+ 首页菜单bug根因

## 目标
祥哥要的浮窗菜单**按 TikTok 页面不同**显示 → 必须先**准确识别手机当前页**，且要压掉"多页面共享控件"造成的误判。

## 完成（全部真机实测通过）

### 1. 实时识别闭环（端到端可跑）
```
浏览器 http://127.0.0.1:8091/  点"扫描"按钮
  → live_scan_bridge.py (本机8091, FastAPI)
  → 云端 POST /command action=ui_scan
  → 手机轮询(~1s)执行 → HTTP 上报
  → 云端缓存到内存 _last_ui_scan[device_id]
  → 桥接轮询 GET /devices/{id}/ui-scan/ 直到 ts 变化
  → 本地 recognize() → 返回 页面/分数/证据/固定控件
```
- **连接拓扑关键认知**：手机走 **HTTP 轮询**（`GET /ws/{device}/poll?secret=...` → 204）**不是 WebSocket**！所以 `get_online_devices()` 只列 WS 连接 → 显示 0 是**正常**的，别当故障。指令照常排队下发。
- 云端部署：`/opt/xnow-flow`（flat 结构，uvicorn main:app --port 8000，systemd 服务 `xnow-backend`）。改的是 `routers/ws.py`（ui_scan 分支加缓存）+ `routers/device_commands.py`（加 GET ui-scan 接口）。备份 .bak-20260814 在服务器上。
- **ui_scan 返回键**：`{count, elements:[{class,x,y,frame,acc_id}]}` —— **没有 label/acc_label/isSelected**！判固定/变量只用 class+acc_id+x/y。
- 凭证读取：`ssh_upload.py`/`ssh_run.py` 用 paramiko + `.env.local` 的 XNW_VPS_PASSWORD（**禁止输出凭证**）。本地上传用 base64 走 exec（SFTP 不稳）；Git Bash 要 `export MSYS2_ARG_CONV_EXCL='*'`。
- 桥接重启：`Stop-Process` 旧 python + `Start-Process` 全路径（相对路径会失败）。**改了 page_recognizer.py 必须重启桥接**（启动时 import）。

### 2. 六页识别签名（backend/page_recognizer.py）
| 页 | 分/阈值 | 锚点 |
|---|---|---|
| feed 首页 | 11/3 | acc_id: top_tabs_recomend/feedLikeButton/exploretab… |
| profile 我的 | 15/3 | acc_id: TTKProfileTabVideoButton_0/relation_info_* |
| inbox 收件箱 | 7/3 | 类名: TTKInboxActivityStatusView 等（无acc_id） |
| friends 朋友页 | 6/3 | 类名: TTKFriendsFeedTableViewCell 等 |
| search 搜索 | 7/3 | 类名: AWESearchBar + TTKSearch* |
| recorder 录制/创作页 | 16/3 | acc_id: recorderPageToolBar* / recordPage*（10锚点） |

- **算法**：acc_id 或类名加权投票 → 最高分页 → ≥阈值3才判中，否则"未知"；屏外预加载（y>736）过滤。
- **跨页共享控件实战处理**：搜索框 AWESearchBar 在朋友页也有 → 靠 friends 专属类名(6分)压过 search(3分) 最高分裁决；底部 tab 每页都有但没人给它们签名，无影响。**这是祥哥担心的"多个页面有相同控件"案例，已验证解决**。
- 离线交叉验证：`verify_all_pages.py` 跑 6 份存档 `live_scan*.json`（每页换真机扫出来的），6/6 ✓ 零误判。
- 辅助文件：`fetch_scan.py`（拉云端原始 ui_scan 存档）、`live_scan_bridge.py`、`live_scan.html`、`verify_all_pages.py`、`ssh_upload.py`、`ssh_run.py`。

## 首页菜单 bug 根因（不是配置问题！）
祥哥报"首页浮窗菜单不对"。查证：**手机上是 8/12 旧包，缺 8/14 的页面判定修复**（git 提交 c0c8164/0e280b6/c7458a4：隐藏视图过滤、LIVE 徽章防误判、私信标题限位）。识别逻辑在 iOS 端 `CommandEngine.m _detectPageOnMain`（优先级 live>comment>inbox>profile>home）+ `XNFloatingPanel.m _buildPageMenu`（live/inbox/profile/comment 专属，其余→`_mainMenu` 13项）。

## 待办（新对话接力点）
1. **重打包**（祥哥之前说"等一等"，现在识别全完了可推进）：一次打包带上
   - ① 8/14 页面判定修复（首页菜单恢复 13 项完整）
   - ② 截图上传（`_performScreenshot` CommandEngine.m:1187 目前只存相册，需加 [XNURLProtocol sendMessage] 上报 → 电脑能看真机画面）
   - ③ 各页专属菜单（首页=完整13项，其它页=祥哥定的专属功能；**recorder 录制页菜单祥哥还没定**）
2. 发版门禁：攒批一次发（页面修复+截图+菜单）→ CI `build-dylib.yml`（push ios-plugin/** 触发 macOS 构建）→ 装机验证
3. 记忆/文档：这次核心认知（HTTP轮询拓扑/识别签名/首页bug根因）已同步到 project-xnow-flow-setup.md

## 连接信息
- 云端 192.129.210.52:8000（域名 yunkong.taikon.top 走 Cloudflare 同源）
- 手机 iphone_0ECF42DC（IP 64.186.242.99）
- 本机桥接 http://127.0.0.1:8091/
