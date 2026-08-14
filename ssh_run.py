# -*- coding: utf-8 -*-
"""通过 paramiko 在云服务器上执行命令。用法:
    uv run --with paramiko python ssh_run.py "<shell命令>"
凭证从环境变量读取（不落盘、不打印）。
"""
import os, sys, io

HOST = "192.129.210.52"
USER = "root"
PWD = os.environ.get("XNW_VPS_PASSWORD", "")

import paramiko

cmd = sys.argv[1] if len(sys.argv) > 1 else "whoami"
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(HOST, username=USER, password=PWD, timeout=15)
stdin, stdout, stderr = client.exec_command(cmd, timeout=30)
out = stdout.read().decode("utf-8", "replace")
err = stderr.read().decode("utf-8", "replace")
if out.strip():
    print(out.rstrip())
if err.strip():
    print("[stderr]", err.rstrip())
client.close()
