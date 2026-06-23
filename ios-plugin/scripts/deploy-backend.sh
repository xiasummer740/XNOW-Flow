#!/bin/bash
# deploy-backend.sh — XNOW 后端一键部署脚本（VPS Ubuntu 20.04）
# 用法: bash deploy-backend.sh
# 需要在 VPS 上以 root 运行

set -euo pipefail

echo "============================================"
echo " XNOW 后端一键部署"
echo " 目标: $(hostname) ($(curl -s ifconfig.me 2>/dev/null || echo 'unknown'))"
echo "============================================"

# ---- 配置 ----
APP_DIR="/opt/xnow-flow"
BACKUP_DIR="/opt/xnow-flow-backup"
REPO_URL="https://github.com/xiasummer740/XNOW-Flow.git"
PORT=8000

# ---- Step 1: 安装系统依赖 ----
echo ""
echo "[1/6] 安装系统依赖..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv nginx git curl ufw

# ---- Step 2: 备份旧版本 ----
echo ""
echo "[2/6] 备份旧版本..."
if [ -d "$APP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
    cp -a "$APP_DIR" "$BACKUP_DIR"
    echo "  已备份到 $BACKUP_DIR"
fi

# ---- Step 3: 拉取代码 ----
echo ""
echo "[3/6] 拉取最新代码..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"

if [ -d "$APP_DIR/.git" ]; then
    git pull
else
    # 先尝试从 GitHub 拉取
    if git clone "$REPO_URL" /tmp/xnow-tmp 2>/dev/null; then
        cp -r /tmp/xnow-tmp/backend/* "$APP_DIR/"
        rm -rf /tmp/xnow-tmp
    else
        echo "  GitHub 拉取失败，请手动上传 backend/ 目录到 $APP_DIR"
        echo "  可以用 scp 或 sftp"
        exit 1
    fi
fi

mkdir -p "$APP_DIR/data" "$APP_DIR/static" "$APP_DIR/uploads"

# ---- Step 4: 安装 Python 依赖 ----
echo ""
echo "[4/6] 安装 Python 依赖..."
python3 -m venv "$APP_DIR/venv" 2>/dev/null || true

# 生成兼容的 requirements
cat > "$APP_DIR/requirements-compat.txt" << 'EOF'
fastapi==0.110.0
uvicorn==0.29.0
sqlalchemy==2.0.30
pyjwt==2.8.0
pydantic==2.7.1
pydantic-settings==2.2.1
python-multipart==0.0.9
aiofiles==23.2.1
websockets>=10.0
pycryptodome>=3.10
EOF

"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements-compat.txt" -q

# ---- Step 5: 配置 systemd 服务 ----
echo ""
echo "[5/6] 配置 systemd 服务..."
cat > /etc/systemd/system/xnow-backend.service << 'SERVICE'
[Unit]
Description=XNOW Flow Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/xnow-flow
Environment=PATH=/opt/xnow-flow/venv/bin:/usr/bin
ExecStart=/opt/xnow-flow/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
StartLimitInterval=0
StandardOutput=append:/opt/xnow-flow/server.log
StandardError=append:/opt/xnow-flow/server.log

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable xnow-backend
systemctl restart xnow-backend

echo "  服务状态:"
systemctl status xnow-backend --no-pager | head -5

# ---- Step 6: 防火墙 & 验证 ----
echo ""
echo "[6/6] 配置防火墙并验证..."
ufw allow "$PORT/tcp" 2>/dev/null || true
ufw allow 22/tcp 2>/dev/null || true

# 等服务启动
sleep 3

echo ""
echo "============================================"
echo " 验证服务..."

if curl -sf http://localhost:$PORT/docs > /dev/null 2>&1; then
    echo "  ✅ API Docs: http://$(curl -s ifconfig.me 2>/dev/null):$PORT/docs"
    echo "  ✅ WebSocket: ws://$(curl -s ifconfig.me 2>/dev/null):$PORT/ws/{device_id}"
    echo ""
    echo "  登录信息:"
    echo "    用户名: admin"
    echo "    密码:   admin"
else
    echo "  ❌ 服务启动失败，检查日志:"
    tail -20 "$APP_DIR/server.log" 2>/dev/null || true
fi

echo ""
echo "============================================"
echo " 部署完成！"
echo " 后端路径: $APP_DIR"
echo " 日志文件: $APP_DIR/server.log"
echo " 重启服务: systemctl restart xnow-backend"
echo "============================================"
