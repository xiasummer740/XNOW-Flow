#!/usr/bin/env python3
"""正确重启 xnow-backend.service"""
import paramiko, os, sys

HOST = '192.129.210.52'; USER = 'root'; PROJECT = os.path.dirname(os.path.abspath(__file__))
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
        for line in err.strip().split('\n')[-10:]:
            print(f"  ERR: {line}")
    return out, ec

print("[1] Restart xnow-backend.service...")
run("systemctl restart xnow-backend.service && sleep 4 && systemctl is-active xnow-backend.service", 40)
print("[2] Health check...")
run("curl -s -o /dev/null -w 'HTTP %{http_code}\\n' http://127.0.0.1:8000/", 30)
print("[3] Verify new code loaded (grep _mark_task_from_result)...")
run("grep -c '_mark_task_from_result' /opt/xnow-flow/routers/ws.py; grep -c '远程指令 route 已即时下发' /opt/xnow-flow/task_engine.py", 30)
ssh.close()
print("=== Done ===")
