# -*- coding: utf-8 -*-
"""监控 VPS server.log 备份事件：装机/激活/备份账号。有事件就打一行，无事件静默。断线自动重连。"""
import paramiko, os, sys, time

def load_env():
    env = {}
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env.local'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('='); env[k.strip()] = v.strip()
    return env

PWD = load_env().get('XNW_VPS_PASSWORD', '')
if not PWD:
    print("❌ no password"); sys.exit(1)

CMD = ("tail -F -n 0 /opt/xnow-flow/server.log | grep --line-buffered -E "
       "'account_backed_up|backup|备份|activate|激活|license|licensed|device_bind|device_id|授权|已激活|check_device'")

def connect():
    for attempt in range(5):
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect('192.129.210.52', 22, 'root', PWD, timeout=15)
            return ssh
        except Exception as e:
            print(f"[reconnect {attempt+1}] {type(e).__name__}: {str(e)[:120]}", flush=True)
            time.sleep(5)
    return None

while True:
    ssh = connect()
    if not ssh:
        sys.exit(1)
    try:
        _, stdout, _ = ssh.exec_command(CMD, timeout=0, get_pty=True)
        while True:
            line = stdout.readline()
            if not line:
                # 流结束（断线/连接被服务端关闭）→ 外层重连
                break
            sys.stdout.write(line)
            sys.stdout.flush()
    except Exception as e:
        print(f"[stream error] {type(e).__name__}: {str(e)[:120]}", flush=True)
    try:
        ssh.close()
    except Exception:
        pass
    time.sleep(3)
