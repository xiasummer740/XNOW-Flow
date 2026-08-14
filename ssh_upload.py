# -*- coding: utf-8 -*-
"""用 exec + base64 上传文件到云服务器（SFTP 不稳定时的替代）。用法:
    uv run --with paramiko python ssh_upload.py <本地路径> <远端路径>
"""
import os, sys, base64

HOST = "192.129.210.52"
USER = "root"
PWD = os.environ.get("XNW_VPS_PASSWORD", "")

import paramiko

local = sys.argv[1]
remote = sys.argv[2]
with open(local, "rb") as f:
    data = base64.b64encode(f.read()).decode()

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(HOST, username=USER, password=PWD, timeout=15)
stdin, stdout, stderr = client.exec_command(
    f"base64 -d > {remote} && echo UPLOAD_OK:{remote}",
    timeout=30,
)
stdin.write(data)
stdin.channel.shutdown_write()
out = stdout.read().decode("utf-8", "replace")
err = stderr.read().decode("utf-8", "replace")
print(out.rstrip() if out.strip() else err.rstrip())
client.close()
