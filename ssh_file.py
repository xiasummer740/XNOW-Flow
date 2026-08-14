# -*- coding: utf-8 -*-
"""paramiko 文件传输。用法:
    下载: uv run --with paramiko python ssh_file.py get <远端路径> <本地路径>
    上传: uv run --with paramiko python ssh_file.py put <本地路径> <远端路径>
凭证从环境变量读取。
"""
import os, sys

HOST = "192.129.210.52"
USER = "root"
PWD = os.environ.get("XNW_VPS_PASSWORD", "")

import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(HOST, username=USER, password=PWD, timeout=15)
sftp = client.open_sftp()

op = sys.argv[1]
if op == "get":
    sftp.get(sys.argv[2], sys.argv[3])
    print(f"已下载: {sys.argv[3]} ({os.path.getsize(sys.argv[3])} bytes)")
elif op == "put":
    sftp.put(sys.argv[2], sys.argv[3])
    print(f"已上传: {sys.argv[3]}")
sftp.close()
client.close()
