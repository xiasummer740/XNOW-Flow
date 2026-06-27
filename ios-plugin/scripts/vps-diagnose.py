#!/usr/bin/env python3
"""上传 IPA 到 VPS 并运行二进制诊断"""

import paramiko, os, sys

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

LOCAL_IPA = os.path.join(PROJECT_DIR, "TikTok_XNOW_v2.ipa")
LOCAL_CHECKER = os.path.join(SCRIPTS_DIR, "vps-check-macho.py")

REMOTE_DIR = "/root/xnow-diagnose"
REMOTE_IPA = f"{REMOTE_DIR}/TikTok_XNOW_v2.ipa"
REMOTE_CHECKER = f"{REMOTE_DIR}/check.py"


def main():
    print("=" * 60)
    print("  XNOW IPA 诊断工具")
    print("=" * 60)

    if not os.path.exists(LOCAL_IPA):
        print(f"[ERR] IPA not found: {LOCAL_IPA}")
        sys.exit(1)

    print(f"\n[1/4] 连接 VPS ...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)
    ssh.exec_command(f"mkdir -p {REMOTE_DIR}")
    print("  [OK]")

    print(f"\n[2/4] 上传 IPA ({os.path.getsize(LOCAL_IPA)/1024/1024:.0f} MB)...")
    sftp = ssh.open_sftp()
    sftp.put(LOCAL_IPA, REMOTE_IPA)
    print("  [OK]")

    print(f"\n[3/4] 上传诊断脚本 ...")
    sftp.put(LOCAL_CHECKER, REMOTE_CHECKER)
    sftp.close()
    print("  [OK]")

    print(f"\n[4/4] 运行诊断 ...")
    stdin, stdout, stderr = ssh.exec_command(
        f"cd {REMOTE_DIR} && python3 check.py {REMOTE_IPA}",
        timeout=120
    )
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')

    for line in out.split("\n"):
        if line.strip():
            print(f"  {line}")

    if err.strip():
        print(f"\n  STDERR: {err.strip()[:500]}")

    ssh.exec_command(f"rm -rf {REMOTE_DIR}")
    ssh.close()

    if exit_code != 0:
        print(f"\n[ERR] 诊断脚本退出码: {exit_code}")
        sys.exit(1)


if __name__ == "__main__":
    main()
