#!/usr/bin/env python3
"""在 VPS 上启动 HTTP 服务（假设 IPA 已存在）"""
import paramiko, os, sys, time

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"

REMOTE_DIR = "/root/xnow-inject"


def main():
    print("=" * 60)
    print("  VPS IPA HTTP 服务 (快速版)")
    print("=" * 60)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)

    # Check existing IPA files
    _, stdout, _ = ssh.exec_command("ls -lh /root/xnow-inject/TikTok_42.2.0_BH.ipa /opt/xnow-flow/TikTok_42.2.0_BH.ipa 2>/dev/null")
    existing = stdout.read().decode()
    print(f"\n[1] 检查已有 IPA:")
    print(f"  {existing.strip()}")

    # Pick the one that exists
    ipa_path = None
    for p in ["/root/xnow-inject/TikTok_42.2.0_BH.ipa", "/opt/xnow-flow/TikTok_42.2.0_BH.ipa"]:
        _, check, _ = ssh.exec_command(f"test -f {p} && echo YES || echo NO")
        if check.read().decode().strip() == "YES":
            ipa_path = p
            break

    if not ipa_path:
        print(f"\n[ERR] 未找到 IPA 文件！请先上传")
        ssh.close()
        sys.exit(1)

    # Kill existing http.server processes
    ssh.exec_command("pkill -f 'http.server 9999' 2>/dev/null; sleep 0.5")

    # Start HTTP server
    dir_path = os.path.dirname(ipa_path)
    print(f"\n[2] 启动 HTTP 服务 (目录: {dir_path}) ...")
    ssh.exec_command(f"cd {dir_path} && nohup python3 -m http.server 9999 --bind 0.0.0.0 > /dev/null 2>&1 &")
    time.sleep(1)

    # Verify
    _, stdout, _ = ssh.exec_command("curl -s -o /dev/null -w '%{http_code}' http://localhost:9999/TikTok_42.2.0_BH.ipa", timeout=10)
    http_code = stdout.read().decode().strip()
    if http_code == "200":
        url = f"http://{HOST}:9999/TikTok_42.2.0_BH.ipa"
        _, out_size, _ = ssh.exec_command(f"stat -c%s {ipa_path}")
        size = int(out_size.read().decode().strip() or 0)
        print(f"  [OK] HTTP 服务运行中")
        print(f"\n  IPA 链接: {url}")
        print(f"  大小: {size/1024/1024:.0f} MB")
    else:
        print(f"  [ERR] HTTP 服务异常 (HTTP {http_code})")

    ssh.close()
    print(f"\n{'='*60}")
    print(f"  现在用这个链接触发 GitHub Actions:")
    print(f"  gh workflow run ... -f inject_ipa_url=http://{HOST}:9999/TikTok_42.2.0_BH.ipa")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
