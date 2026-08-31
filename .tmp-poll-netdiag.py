# 一次性：ssh VPS tail server.log 找 net_diag 上报结果（前端执行结果区不回显时用）
import paramiko, os, sys

env = {}
for line in open('.env.local', encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, _, v = line.partition('='); env[k.strip()] = v.strip()
PWD = env.get('XNW_VPS_PASSWORD', '')

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', PWD, timeout=15)

# 找 server.log 位置并 tail 最近 200 行，过滤 net_diag / result / XNOWER
cmd = ("LOG=$(ls -t /opt/xnow-flow/*.log /opt/xnow-flow/logs/*.log 2>/dev/null | head -1); "
       "echo \"LOG=$LOG\"; "
       "tail -n 300 \"$LOG\" | grep -iE 'net_diag|xnower|session|hits|registered|result|device.*13|上报' | tail -n 60")
_, stdout, stderr = ssh.exec_command(cmd, timeout=30)
out = stdout.read().decode('utf-8', errors='replace')
print(out)
if not out.strip():
    # 兜底：直接列最近日志
    _, o2, _ = ssh.exec_command("ls -lt /opt/xnow-flow/*.log 2>/dev/null | head -5; ls -lt /opt/xnow-flow/logs/*.log 2>/dev/null | head -5", timeout=15)
    print("[no match] 最近日志文件:")
    print(o2.read().decode('utf-8', errors='replace'))
ssh.close()
