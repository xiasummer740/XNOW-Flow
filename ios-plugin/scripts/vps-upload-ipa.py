#!/usr/bin/env python3
"""
vps-upload-ipa.py — 上传 IPA + dylib 到 VPS，在 VPS 上注入，下载回本地
用法: python vps-upload-ipa.py

流程:
  1. 上传 TikTok_42.2.0_BH.ipa + xnower.dylib + vps-inject.py → VPS
  2. 在 VPS 上运行注入
  3. 下载 TikTok_XNOW.ipa 回本地
"""

import paramiko, os, sys, time

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"
PORT = 22

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

LOCAL_IPA = os.path.join(PROJECT_DIR, "TikTok_43.7.0_BH.ipa")
LOCAL_DYLIB = os.path.join(PROJECT_DIR, "build-artifacts-ci", "xnower-lld-converted.dylib")
LOCAL_VPS_INJECT = os.path.join(SCRIPTS_DIR, "vps-inject.py")

REMOTE_DIR = "/root/xnow-inject"
REMOTE_IPA = f"{REMOTE_DIR}/TikTok_43.7.0_BH.ipa"
REMOTE_DYLIB = f"{REMOTE_DIR}/xnower.dylib"
REMOTE_INJECT = f"{REMOTE_DIR}/vps-inject.py"
REMOTE_OUTPUT = f"{REMOTE_DIR}/TikTok_XNOW.ipa"
LOCAL_OUTPUT = os.path.join(PROJECT_DIR, "TikTok_XNOW_v16.ipa")


def check_files():
    ok = True
    for name, path in [("IPA", LOCAL_IPA), ("dylib", LOCAL_DYLIB), ("inject", LOCAL_VPS_INJECT)]:
        if not os.path.exists(path):
            print(f"  [ERR] 缺少 {name}: {path}")
            ok = False
        else:
            size = os.path.getsize(path)
            unit = "MB" if size > 1024*1024 else "KB"
            div = 1024*1024 if size > 1024*1024 else 1024
            print(f"  [OK] {name}: {size/div:.1f} {unit}")
    return ok


def upload(ssh, local, remote, label):
    size = os.path.getsize(local)
    print(f"  [UP] 上传 {label} ({size/1024/1024:.1f} MB)...", end="", flush=True)
    sftp = ssh.open_sftp()
    sftp.put(local, remote, callback=lambda x, t: None)
    sftp.close()
    print(" done")


def download(ssh, remote, local, label):
    print(f"  [DL] 下载 {label}...", end="", flush=True)
    sftp = ssh.open_sftp()
    sftp.get(remote, local)
    sftp.close()
    size = os.path.getsize(local)
    print(f" done ({size/1024/1024:.1f} MB)")


def main():
    print("=" * 60)
    print("  XNOW IPA 注入工具 (VPS 版)")
    print("=" * 60)

    if not check_files():
        sys.exit(1)

    print(f"\n[1/5] 连接 VPS {HOST} ...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(HOST, PORT, USER, PASSWORD, timeout=15)
        print("  [OK] 连接成功")
    except Exception as e:
        print(f"  [ERR] 连接失败: {e}")
        sys.exit(1)

    ssh.exec_command(f"mkdir -p {REMOTE_DIR}")

    print(f"\n[2/5] 上传文件到 VPS ...")
    upload(ssh, LOCAL_IPA, REMOTE_IPA, "IPA")
    upload(ssh, LOCAL_DYLIB, REMOTE_DYLIB, "dylib")
    upload(ssh, LOCAL_VPS_INJECT, REMOTE_INJECT, "注入脚本")

    print(f"\n[3/5] VPS 上运行注入 ...")
    cmd = f"cd {REMOTE_DIR} && python3 vps-inject.py {REMOTE_IPA} {REMOTE_DYLIB} {REMOTE_OUTPUT}"
    print(f"  $ {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=600)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')

    for line in out.split("\n"):
        if line.strip():
            try:
                print(f"  {line}")
            except UnicodeEncodeError:
                print(f"  {line.encode('ascii', errors='replace').decode('ascii')}")
    if err.strip():
        print(f"  STDERR: {err.strip()[:300]}")

    if exit_code != 0:
        print(f"\n  [ERR] 注入失败 (exit={exit_code})")
        ssh.close()
        sys.exit(1)

    print(f"\n[4/5] 下载注入后的 IPA ...")
    download(ssh, REMOTE_OUTPUT, LOCAL_OUTPUT, "注入后 IPA")

    # Check if remote file exists
    _, check, _ = ssh.exec_command(f"ls -lh {REMOTE_OUTPUT}")
    print(f"  VPS端: {check.read().decode().strip()}")

    ssh.close()

    print(f"\n[5/5] 清理临时文件 ...", end="")
    ssh2 = paramiko.SSHClient()
    ssh2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh2.connect(HOST, PORT, USER, PASSWORD, timeout=15)
    ssh2.exec_command(f"rm -rf {REMOTE_DIR}")
    ssh2.close()
    print(" done")

    local_size = os.path.getsize(LOCAL_OUTPUT)
    print(f"\n{'='*60}")
    print(f"  完成!")
    print(f"  输出: {LOCAL_OUTPUT}")
    print(f"  大小: {local_size/1024/1024:.1f} MB")
    print(f"\n  下一步: 用 爱思助手 企业签名 -> 安装到 iPhone 验证")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
