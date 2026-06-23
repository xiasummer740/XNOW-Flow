# XNOW iOS 注入插件

> TikTok 注入插件，通过 WebSocket 连接 XNOW 后端，实现远程自动化控制。

---

## 📋 整体流程

```
 你 (Win11)          GitHub              VPS (Ubuntu)          iPhone
  │                    │                    │                    │
  ├─ push 代码 ──────→│                    │                    │
  │                    ├─ macOS 编译 dylib │                    │
  │                    ├─ 注入 TikTok IPA  │                    │
  │                    ├─ 输出修改后 IPA ──→│ (下载)             │
  │                    │                    ├─ TrollStore 安装 ─→│
  │                    │                    │                    ├─ TikTok 启动
  │                    │                    │                    ├─ dylib 自动加载
  │                    │                    │                    ├─ WebSocket 连接 ─→
  │                    │                    │←───────────────────┤ 状态上报
  │                    │  Dashboard 控制 ──→├─ 下发指令 ────────→│ 执行操作
```

---

## 🚀 完整步骤

### 第一步：设置 VPS 后端

```bash
# 在 Windows 上运行（需要 Python + paramiko）
cd ios-plugin/scripts
python vps-setup.py
```

脚本会自动完成：
- ✅ 安装 Python 3.8 + 依赖
- ✅ 上传后端代码
- ✅ 配置 systemd 服务（开机自启）
- ✅ 启动后端（端口 8000）
- ✅ 配置防火墙

**验证后端：**
浏览器打开 `http://192.129.210.52:8000/docs`，能看到 Swagger API 文档即成功。

**登录信息：** `admin` / `admin`
**登录接口：** `POST /api/auth/login/`

---

### 第二步：获取砸壳 TikTok IPA

> 苹果 App Store 下载的 TikTok 是加密的，需要"砸壳"（解密）才能注入。

**方法一：从第三方网站下载（最简单）**
- 搜索 "TikTok decrypted IPA" 或 "TikTok 砸壳 IPA"
- 常用站点：iOSGods, AppCake, 各大 IPA 分享站
- 注意找最新版本的 TikTok IPA

**方法二：自己砸壳（需要越狱设备）**
1. 在越狱 iPhone 上安装 `frida` + `bfinject` 或 `CrackerXI+`
2. 运行砸壳工具获取解密 IPA
3. 通过 AirDrop 或文件传输传到电脑

**方法三：用 GitHub Actions 自动下载（如果有直链）**
- 找个稳定的 IPA 下载链接
- 后续通过 GitHub Actions workflow_dispatch 传入链接

---

### 第三步：编译 dylib + 注入 IPA

#### 方式 A：GitHub Actions（推荐）

```bash
# 1. 先推送代码到 GitHub
# 你的仓库已经在了: https://github.com/xiasummer740/XNOW-Flow

# 2. 修改 config。如果你改了 VPS IP，编辑以下文件:
#    ios-plugin/xnow-dylib/Config.plist 里的 XNOWER_ServerURL

# 3. 本地提交并推送
git add ios-plugin/
git commit -m "feat: add iOS injection plugin"
git push

# 4. 去 GitHub 仓库页面:
#    Actions → Build XNOW Dylib → Run workflow
#    可选: 填入 IPA 下载链接（如果已有）
#    可选: 修改服务器地址
```

**等待 ~3 分钟，下载 artifacts：**
- `xnower-dylib` — 编译好的 dylib（如果你自己手动注入）
- `TikTok_XNOW.ipa` — 注入完成的 IPA（如果你提供了 IPA 链接）

#### 方式 B：本地编译（需要 Mac）

```bash
# 在 Mac 上
cd ios-plugin/xnow-dylib
make release

# 输出: build/xnower.dylib
```

#### 方式 C：找人代编译

如果不想折腾 GitHub Actions 或没有 Mac，可以把源码发给有 Mac 的朋友：
```
ios-plugin/xnow-dylib/ 目录所有文件
```
运行 `make dylib` 即可编译。

---

### 第四步：安装到 iPhone

#### 前提：安装 TrollStore（巨魔商店）

> ⚠️ iOS 16.7.15 安装 TrollStore 可能受限，先试试看，不行用备选。

**安装方法：**
1. 电脑浏览器打开 https://altstore.io 下载 AltStore
2. 用 Apple ID 登录 AltStore（免费）
3. iPhone 连电脑，AltStore 安装到手机
4. 手机打开 AltStore → 安装 TrollStore
5. TrollStore 安装完成后，用它安装 IPA

**备选安装方法（如果没有 TrollStore）：**
- **AltStore**: 每 7 天需要电脑重新签名
- **Sideloadly**: 同样 7 天过期
- **开发者账号 ($99/年)**: 一年有效
- **企业签服务**: 淘宝可买，一般 1-3 个月

#### 安装 IPA

1. 把 `TikTok_XNOW.ipa`（或你自己注入的 IPA）传到 iPhone
   - 可以用 iCloud、AirDrop、或者自建 HTTP 下载
2. 用 TrollStore 打开 IPA 文件 → 自动安装
3. 如果没有 TrollStore:
   - 电脑装 AltStore → iPhone 连电脑 → 拖入 IPA 安装

---

### 第五步：验证连接

1. 手机上打开 TikTok（图标不变，但内部已注入插件）
2. 插件会在后台自动连接 WebSocket
3. 打开 XNOW 后台 Dashboard:
   ```
   http://192.129.210.52:8000/docs#/Device
   ```
   或者在**前端页面**查看设备列表

4. 看到你的 iPhone 在线（设备 ID: `iphone_xxxxxxxx`）
5. 下发指令测试：
   ```
   POST /api/biz/v2/devices/{device_id}/command/
   {"action": "scroll_down", "params": {}}
   ```

---

## 📂 文件结构

```
ios-plugin/
├── xnow-dylib/                    # dylib 源码
│   ├── XNOWER.h / .m             # 主入口 + 生命周期
│   ├── WsClient.h / .m           # WebSocket 客户端（NSURLSessionWebSocketTask）
│   ├── CommandEngine.h / .m      # 指令执行引擎
│   ├── DeviceStatus.h / .m       # 设备状态采集
│   ├── TikTokHooks.h / .m        # TikTok 运行时 hooks
│   ├── Config.plist               # 默认配置文件
│   └── Makefile                   # macOS 编译脚本
├── scripts/
│   ├── inject-ipa.sh              # IPA 注入脚本（macOS）
│   ├── deploy-backend.sh          # VPS 部署脚本（Ubuntu）
│   └── vps-setup.py               # VPS 一键部署（Windows）
├── .github/workflows/
│   └── build-dylib.yml            # GitHub Actions 流水线
└── README.md                      # 本文件
```

---

## ⚙️ 配置说明

### 修改服务器地址

编辑 `ios-plugin/xnow-dylib/Config.plist`:

```xml
<key>XNOWER_ServerURL</key>
<string>ws://你的VPS_IP:8000</string>
```

或者在 iPhone 上通过 NSUserDefaults 修改（需要越狱或开发者模式）：
```bash
defaults write com.zhiliaoapp.musically XNOWER_ServerURL "ws://新地址:8000"
defaults write com.zhiliaoapp.musically XNOWER_Enabled 1
```

### 支持的指令

| 指令 | 参数 | 说明 |
|------|------|------|
| `scroll_down` | - | 上滑（下一个视频）|
| `scroll_up` | - | 下滑（上一个视频）|
| `like` | - | 点赞当前视频 |
| `follow` | - | 关注作者 |
| `comment` | `{"text": "Nice!"}` | 评论 |
| `collect` | - | 收藏 |
| `screenshot` | - | 截图 |
| `open_profile` | `{"username": "xxx"}` | 打开用户主页 |
| `collect_fans` | `{"count": 20}` | 采集粉丝列表 |
| `collect_videos` | `{"count": 10}` | 采集视频列表 |
| `batch_like` | `{"count": 5, "interval": 2}` | 批量点赞 |
| `batch_follow` | `{"count": 5, "interval": 3}` | 批量关注 |
| `batch_comment` | `{"count": 5, "text": "Hi!", "interval": 5}` | 批量评论 |

---

## 🔧 自建调试浮窗

在 TikTok 运行时，启用调试浮窗可以看到连接状态：

```objc
// 在 XNOWER.m 的 start 方法中取消注释:
// [self showDebugOverlay];
```

或者通过 SSH 到 iPhone 执行（越狱设备）：
```bash
defaults write com.zhiliaoapp.musically XNOWER_DebugOverlay 1
```

---

## 🐛 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| 设备不显示在线 | WebSocket 连接失败 | 检查 VPS 端口 8000 是否开放；检查 iOS 网络 |
| 插件没生效 | dylib 注入失败 | 重新注入 IPA，确认 Binary 有 LC_LOAD_DYLIB |
| TikTok 闪退 | dylib 兼容性问题 | 检查 iOS 版本；用 `make debug` 编译看日志 |
| 指令执行无反应 | TikTok UI 变化 | 用 accessibility inspector 看当前 UI 层级 |
| 连接不稳定 | 网络或心跳问题 | 调整 `Config.plist` 心跳间隔 |
| TrollStore 装不上 | iOS 版本问题 | 换 AltStore 或购买企业签 |

---

## 📝 日志查看

dylib 运行日志写入 iPhone 的 Documents 目录：
```
手机文件系统/Apps/TikTok/Documents/xnower.log
```

查看方法（越狱设备）：
```bash
ssh root@设备IP
cat /var/mobile/Containers/Data/Application/XXXXXXXX/Documents/xnower.log
```

非越狱设备可以通过 Xcode → Devices and Simulators → 选择设备 → Download Container 查看。

---

## 🔄 更新插件

1. 修改源码
2. `git push` → GitHub Actions 自动编译
3. 下载新的 dylib
4. 重新注入 → 重新签名 → 重新安装 IPA
5. 或者只替换已安装 App 的 dylib（越狱设备）：
   ```bash
   scp xnower.dylib root@设备IP:/path/to/TikTok.app/Frameworks/
   ```

---

## 📌 注意事项

- **TikTok 版本更新**可能改变 UI 层级，导致坐标点击失效。此时需更新 `CommandEngine.m`。
- **不要在大号上测试**，建议用小号或测试账号。
- **频率控制**：批量操作建议间隔 >= 2 秒，太快会被 TikTok 风控。
- **iOS 网络**：确保 iPhone 能访问 VPS 的 8000 端口（VPS 防火墙已配置）。
