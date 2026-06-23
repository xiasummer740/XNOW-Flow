#!/usr/bin/env python3
"""
vps-setup.py — XNOW VPS 一键部署脚本（在 Windows 上用 paramiko 执行）
用法: python vps-setup.py

自动完成:
  1. 上传后端代码到 VPS
  2. 安装 Python 依赖
  3. 配置 systemd 服务
  4. 启动后端
  5. 配置防火墙
"""

import paramiko
import os
import sys
import time

# ======== 配置 ========
HOST = "192.129.210.52"
PORT = 22
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"
BACKEND_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "backend")
REMOTE_DIR = "/opt/xnow-flow"

def run(ssh, cmd, check=True, timeout=60):
    """在 VPS 上执行命令"""
    print(f"  $ {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    exit_status = stdout.channel.recv_exit_status()
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out:
        for line in out.split("\n")[:10]:
            print(f"    {line}")
    if err and exit_status != 0:
        for line in err.split("\n")[:5]:
            print(f"    ERR: {line}")
        if check:
            sys.exit(1)
    return out, err, exit_status

def main():
    print("=" * 50)
    print("XNOW VPS 一键部署")
    print(f"目标: {USER}@{HOST}:{PORT}")
    print("=" * 50)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    print("\n[1/6] 连接 VPS ...")
    ssh.connect(HOST, PORT, USER, PASSWORD, timeout=30)
    print("  ✅ 已连接")

    print("\n[2/6] 安装系统依赖 ...")
    run(ssh, "apt-get update -qq")
    run(ssh, "apt-get install -y -qq python3 python3-pip python3-venv nginx curl ufw")

    print("\n[3/6] 创建目录并上传后端代码 ...")
    run(ssh, f"mkdir -p {REMOTE_DIR}/data {REMOTE_DIR}/static {REMOTE_DIR}/uploads")

    sftp = ssh.open_sftp()
    uploaded = 0
    for root, dirs, files in os.walk(BACKEND_DIR):
        for d in dirs:
            if d.startswith("__pycache__") or d in (".git", ".venv", "venv"):
                continue
            local_dir = os.path.join(root, d)
            rel = os.path.relpath(local_dir, BACKEND_DIR)
            rem = f"{REMOTE_DIR}/{rel.replace(os.sep, '/')}"
            try:
                sftp.stat(rem)
            except:
                sftp.mkdir(rem)
        for f in files:
            if f.endswith(".pyc"):
                continue
            local_file = os.path.join(root, f)
            rel = os.path.relpath(local_file, BACKEND_DIR)
            rem = f"{REMOTE_DIR}/{rel.replace(os.sep, '/')}"
            sftp.put(local_file, rem)
            uploaded += 1
    sftp.close()
    print(f"  已上传 {uploaded} 个文件")

    print("\n[4/6] 安装 Python 依赖 ...")
    run(ssh, f"cd {REMOTE_DIR} && python3 -m venv venv")

    # 生成兼容 requirements
    req_cmd = f"cat > {REMOTE_DIR}/requirements-compat.txt << 'REQ'\nfastapi==0.110.0\nuvicorn==0.29.0\nsqlalchemy==2.0.30\npyjwt==2.8.0\npydantic==2.7.1\npydantic-settings==2.2.1\npython-multipart==0.0.9\naiofiles==23.2.1\nwebsockets>=10.0\npycryptodome>=3.10\nREQ"
    run(ssh, req_cmd, timeout=10)
    run(ssh, f"{REMOTE_DIR}/venv/bin/pip install -r {REMOTE_DIR}/requirements-compat.txt -q", timeout=120)

    # 验证导入
    run(ssh, f"cd {REMOTE_DIR} && venv/bin/python3 -c 'from main import app; print(f\"OK: {len(app.routes)} routes\")'")

    print("\n[5/6] 配置 systemd 服务 ...")
    service = f"""[Unit]
Description=XNOW Flow Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory={REMOTE_DIR}
Environment=PATH={REMOTE_DIR}/venv/bin:/usr/bin
ExecStart={REMOTE_DIR}/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
StartLimitInterval=0
StandardOutput=append:{REMOTE_DIR}/server.log
StandardError=append:{REMOTE_DIR}/server.log

[Install]
WantedBy=multi-user.target
"""
    run(ssh, f"cat > /etc/systemd/system/xnow-backend.service << 'SERV'\n{service}\nSERV")
    run(ssh, "systemctl daemon-reload")
    run(ssh, "systemctl enable xnow-backend")
    run(ssh, "systemctl restart xnow-backend")
    time.sleep(3)

    print("\n[6/6] 验证服务 & 配置防火墙 ...")
    run(ssh, "ufw allow 8000/tcp 2>/dev/null || true")
    run(ssh, "ufw allow 22/tcp 2>/dev/null || true")

    # 检查服务状态
    out, _, _ = run(ssh, "systemctl is-active xnow-backend", check=False)
    if "active" in out:
        print("\n  ✅ 后端服务运行中")
    else:
        print(f"\n  ❌ 服务状态: {out}")
        run(ssh, f"tail -20 {REMOTE_DIR}/server.log", check=False)

    # 获取公网 IP
    out, _, _ = run(ssh, "curl -s ifconfig.me 2>/dev/null || echo 'unknown'", check=False, timeout=10)
    public_ip = out.strip()

    ssh.close()

    print("\n" + "=" * 50)
    print("🎉 部署完成！")
    print("=" * 50)
    print(f"  API Docs:  http://{public_ip}:8000/docs")
    print(f"  WebSocket: ws://{public_ip}:8000/ws/{{device_id}}")
    print(f"  登录: admin / admin")
    print()
    print(f"  管理命令:")
    print(f"    查看状态: systemctl status xnow-backend")
    print(f"    重启服务: systemctl restart xnow-backend")
    print(f"    查看日志: tail -f {REMOTE_DIR}/server.log")
    print("=" * 50)

if __name__ == "__main__":
    main()
