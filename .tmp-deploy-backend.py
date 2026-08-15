#!/usr/bin/env python3
"""部署后端改动到 VPS：task_engine.py + routers/ws.py，重启 uvicorn"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
REMOTE = '/opt/xnow-flow'
PROJECT = os.path.dirname(os.path.abspath(__file__))

def _load_env():
    env = {}
    with open(os.path.join(PROJECT, '.env.local'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('=')
                env[k.strip()] = v.strip()
    return env

PWD = _load_env().get('XNW_VPS_PASSWORD', '')
if not PWD:
    print('❌ 未读到 XNW_VPS_PASSWORD'); sys.exit(1)

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, 22, USER, PWD, timeout=15)

def run(cmd, timeout=60):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    ec = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        for line in out.strip().split('\n')[-15:]:
            print(f"  {line}")
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-15:]:
            print(f"  ERR: {line}")
    return out, ec

# 0. 探测服务启动方式
print("[0] Probe uvicorn process...")
out, _ = run("ps aux | grep -E 'uvicorn|main:app' | grep -v grep; echo ---; systemctl list-units --type=service 2>/dev/null | grep -iE 'xnow|uvicorn'; echo ---; ls /opt/xnow-flow/ | head -30")

# 1. 上传文件
print("[1] Upload backend files...")
sftp = ssh.open_sftp()
sftp.put(os.path.join(PROJECT, 'backend', 'task_engine.py'), f"{REMOTE}/task_engine.py")
if not os.path.exists(os.path.join(PROJECT, 'backend', 'routers', 'ws.py')):
    print("  ❌ 本地 routers/ws.py 不存在"); sys.exit(1)
run(f"mkdir -p {REMOTE}/routers", 30)
sftp.put(os.path.join(PROJECT, 'backend', 'routers', 'ws.py'), f"{REMOTE}/routers/ws.py")
sftp.close()
print("  uploaded")

# 2. 语法检查（用 venv python）
print("[2] Syntax check on VPS...")
run(f"cd {REMOTE} && venv/bin/python -c \"import ast; ast.parse(open('task_engine.py',encoding='utf-8').read()); ast.parse(open('routers/ws.py',encoding='utf-8').read()); print('syntax OK')\"", 60)

# 3. 重启（systemd 优先，否则找进程）
print("[3] Restart service...")
out, ec = run("systemctl list-units --type=service 2>/dev/null | grep -iE 'xnow|uvicorn'", 20)
if ec == 0 and out.strip():
    svc = out.strip().split()[-1]
    run(f"systemctl restart {svc} && sleep 3 && systemctl is-active {svc}", 40)
else:
    # 用 nohup 方式：找到老进程 PID 杀掉，重新起
    run("pkill -f 'uvicorn main:app' || true", 20)
    run("cd /opt/xnow-flow && nohup venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 >> /opt/xnow-flow/server.log 2>&1 &", 20)
    import time; time.sleep(4)

# 4. 健康检查
print("[4] Health check...")
run("curl -s -o /dev/null -w 'HTTP %{http_code}\\n' http://127.0.0.1:8000/health || echo 'health endpoint not found, checking /'", 30)
run("curl -s http://127.0.0.1:8000/ | head -c 200; echo", 30)

ssh.close()
print("=== Done ===")
