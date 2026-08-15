# -*- coding: utf-8 -*-
"""上传 IPA 到云服务器 static/（带 md5 校验，.uploading → 校验 → mv）。
用法:
    export XNW_VPS_PASSWORD=...
    python upload-ipa.py <本地IPA> <远端目录>
"""
import os, sys, hashlib
import paramiko

HOST = "192.129.210.52"
USER = "root"
PWD = os.environ.get("XNW_VPS_PASSWORD", "")

local = sys.argv[1]
remote_dir = sys.argv[2].rstrip("/")
name = os.path.basename(local)
remote_tmp = f"{remote_dir}/.{name}.uploading"
remote_dst = f"{remote_dir}/{name}"

local_md5 = hashlib.md5(open(local, "rb").read()).hexdigest()
print(f"本地 {name} ({os.path.getsize(local)/1024/1024:.1f}MB) md5={local_md5}")

def _upload():
    local_size = os.path.getsize(local)
    for attempt in range(1, 4):
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(HOST, username=USER, password=PWD, timeout=15)
        try:
            sftp = client.open_sftp()
            # 断点续传：看远端已写多少
            done = 0
            try:
                done = sftp.stat(remote_tmp).st_size
            except FileNotFoundError:
                pass
            if done >= local_size:
                print("远端已上传完整，跳过")
                return client
            if done:
                print(f"续传：远端已有 {done/1024/1024:.1f}MB")
            with open(local, "rb") as fl:
                fl.seek(done)
                with sftp.open(remote_tmp, "ab") as fr:
                    while True:
                        chunk = fl.read(1024 * 1024)
                        if not chunk:
                            break
                        fr.write(chunk)
                        done += len(chunk)
                        if done % (64 * 1024 * 1024) < 1024 * 1024:
                            print(f"  {done/1024/1024:.0f}/{local_size/1024/1024:.0f}MB")
            print(f"上传完成 (第{attempt}次尝试)")
            return client
        except Exception as e:
            client.close()
            print(f"第{attempt}次失败: {repr(e)}")
    raise SystemExit("❌ 3 次尝试均失败，中止")

client = _upload()

# md5 校验
stdin, stdout, stderr = client.exec_command(f"md5sum {remote_tmp}", timeout=60)
remote_md5 = stdout.read().decode().split()[0].strip()
if remote_md5 == local_md5:
    stdin, stdout, stderr = client.exec_command(f"mv {remote_tmp} {remote_dst} && ls -lh {remote_dst}", timeout=30)
    print(stdout.read().decode().strip())
    print(f"✅ 上传并校验成功: {remote_dst}")
else:
    print(f"❌ md5 不一致: 本地={local_md5} 远端={remote_md5}")
client.close()
