#!/usr/bin/env python3
"""在 VPS 上用 HTTP 临时托管 IPA，供 GitHub Actions 下载"""
import paramiko, os, sys, time

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

LOCAL_IPA = os.path.join(PROJECT_DIR, "TikTok_42.2.0_BH.ipa")
REMOTE_DIR = "/opt/xnow-flow"


def main():
    print("=" * 60)
    print("  VPS HTTP IPA 服务器")
    print("=" * 60)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)
    ssh.exec_command(f"mkdir -p {REMOTE_DIR}")

    # Upload IPA
    print(f"\n[1] 上传 IPA 到 VPS ...")
    sftp = ssh.open_sftp()
    ipa_remote = f"{REMOTE_DIR}/TikTok_42.2.0_BH.ipa"
    sftp.put(LOCAL_IPA, ipa_remote)
    sftp.close()
    ipa_size = os.path.getsize(LOCAL_IPA)
    print(f"  [OK] {ipa_remote} ({ipa_size/1024/1024:.0f} MB)")

    # Start HTTP server in background
    print(f"\n[2] 启动 HTTP 服务 (端口 9999) ...")
    http_cmd = f"cd {REMOTE_DIR} && nohup python3 -m http.server 9999 --bind 0.0.0.0 > /dev/null 2>&1 & echo PID=$!"
    _, stdout, _ = ssh.exec_command(http_cmd)
    pid_info = stdout.read().decode()
    print(f"  {pid_info.strip()}")

    # Get public URL
    ip = HOST
    url = f"http://{ip}:9999/TikTok_42.2.0_BH.ipa"
    print(f"\n  IPA 下载地址: {url}")
    print(f"  大小: {ipa_size/1024/1024:.0f} MB")

    # Verify accessible
    time.sleep(1)
    _, stdout, _ = ssh.exec_command(f"curl -sI http://localhost:9999/TikTok_42.2.0_BH.ipa 2>/dev/null | head -5")
    check = stdout.read().decode()
    if '200' in check or 'Content-Length' in check:
        print(f"  [OK] HTTP 服务正常运行")
    else:
        print(f"  [WARN] 可能有问题: {check[:200]}")

    ssh.close()
    print(f"\n{'='*60}")
    print(f"  IPA 地址: {url}")
    print(f"  有效期: 直到 VPS 重启或关闭")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
