#!/usr/bin/env python3
import paramiko
import json

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.129.210.52", 22, "root", "0ISvaWdV88lLq871Re", timeout=30)

# Check active process
stdin, stdout, stderr = ssh.exec_command("ps aux | grep uvicorn | grep -v grep")
print("=== Running processes ===")
print(stdout.read().decode().strip())

# List all routes
stdin, stdout, stderr = ssh.exec_command("cd /opt/xnow-flow && venv/bin/python3 -c 'from main import app\nfor r in app.routes:\n if hasattr(r,\"path\"):\n  print(r.path)'")
print("\n=== Routes ===")
print(stdout.read().decode().strip()[:2000])

# Test login
stdin, stdout, stderr = ssh.exec_command("curl -s -X POST http://localhost:8000/api/biz/v2/user/login -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"admin\"}'")
print("\n=== Login test ===")
login_resp = stdout.read().decode().strip()
print(login_resp[:300] if login_resp else "Empty response")

# Kill old, setup systemd properly
print("\n=== Fixing systemd ===")
ssh.exec_command("pkill -f uvicorn 2>/dev/null; sleep 1")

# Create working service
service = """[Unit]
Description=XNOW Flow Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/xnow-flow
Environment=PATH=/opt/xnow-flow/venv/bin:/usr/bin
ExecStart=/opt/xnow-flow/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=5
StandardOutput=append:/opt/xnow-flow/server.log
StandardError=append:/opt/xnow-flow/server.log

[Install]
WantedBy=multi-user.target
"""

stdin, stdout, stderr = ssh.exec_command(
    "cat > /etc/systemd/system/xnow-backend.service<<'EOF'\n" + service + "EOF\nsystemctl daemon-reload && systemctl enable xnow-backend && systemctl restart xnow-backend"
)
print(stdout.read().decode().strip()[:500])
err = stderr.read().decode().strip()
if err: print("STDERR:", err[:300])

import time
time.sleep(3)

stdin, stdout, stderr = ssh.exec_command("systemctl is-active xnow-backend")
print(f"\nStatus: {stdout.read().decode().strip()}")

ssh.close()
print("\nDone!")
