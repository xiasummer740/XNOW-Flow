#!/usr/bin/env python3
"""vps-reinject.py — 重新注入 dylib 到 IPA 并签名"""
import paramiko, os, sys, tempfile, shutil

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

LOCAL_IPA = os.path.join(PROJECT_DIR, "TikTok_42.2.0_BH.ipa")
LOCAL_DYLIB = os.path.join(PROJECT_DIR, "build-artifacts", "xnower.dylib")
LOCAL_INJECT = os.path.join(SCRIPTS_DIR, "vps-inject.py")

REMOTE_DIR = "/root/xnow-reinject"
REMOTE_IPA = f"{REMOTE_DIR}/bh.ipa"
REMOTE_DYLIB = f"{REMOTE_DIR}/xnower.dylib"
REMOTE_INJECT = f"{REMOTE_DIR}/inject.py"
REMOTE_OUTPUT = f"{REMOTE_DIR}/TikTok_XNOW.ipa"
LOCAL_OUTPUT = os.path.join(PROJECT_DIR, "TikTok_XNOW_v3.ipa")


def run(ssh, cmd, timeout=120):
    _, out, err = ssh.exec_command(cmd, timeout=timeout)
    ec = out.channel.recv_exit_status()
    return out.read().decode('utf-8', errors='replace'), err.read().decode('utf-8', errors='replace'), ec


def main():
    print("=" * 60)
    print("  XNOW IPA 重新注入 + 签名")
    print("=" * 60)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, 22, USER, PASSWORD, timeout=15)

    ssh.exec_command(f"mkdir -p {REMOTE_DIR}")

    print("\n[1] 上传文件 ...")
    sftp = ssh.open_sftp()
    sftp.put(LOCAL_IPA, REMOTE_IPA)
    sftp.put(LOCAL_DYLIB, REMOTE_DYLIB)
    sftp.put(LOCAL_INJECT, REMOTE_INJECT)
    sftp.close()

    print("\n[2] 安装 ldid (伪签名工具) ...")
    out, err, ec = run(ssh, "\n".join([
        "which ldid 2>/dev/null && echo FOUND || (",
        "  cd /tmp &&",
        "  wget -q https://github.com/ProcursusTeam/ldid/raw/main/ldid_linux_x86_64 -O ldid &&",
        "  chmod +x ldid && mv ldid /usr/local/bin/ldid &&",
        "  echo INSTALLED",
        ")",
    ]), 60)
    print(out[:200])

    print("\n[3] 运行注入 ...")
    script = """
import sys, os
sys.path.insert(0, '{rd}')
from inject import inject_ipa

ipa = '{rd}/bh.ipa'
dylib = '{rd}/xnower.dylib'
out = '{rd}/TikTok_XNOW.ipa'

success = inject_ipa(ipa, dylib, out)
if success:
    print('INJECT_OK')
else:
    print('INJECT_FAIL')
    sys.exit(1)
""".format(rd=REMOTE_DIR)
    ssh.exec_command(f"cd {REMOTE_DIR} && python3 -c {shlex.quote(script)}")
    # Run inline
    out, err, ec = run(ssh, f"cd {REMOTE_DIR} && python3 -c 'import sys; sys.path.insert(0,\"{REMOTE_DIR}\"); from inject import inject_ipa; inject_ipa(\"{REMOTE_IPA}\", \"{REMOTE_DYLIB}\", \"{REMOTE_OUTPUT}\")'", 300)
    print(out)
    if ec != 0:
        print(f"[ERR] Inject failed: {err[:300]}")
        ssh.close()
        sys.exit(1)

    print("\n[4] ldid 签名 dylib ...")
    out, err, ec = run(ssh, f"ldid -S {REMOTE_DIR}/TikTok.app/Frameworks/xnower.dylib 2>&1 || echo LIDID_FAIL")
    print(out[:200])

    print("\n[5] 打包 IPA ...")
    out, err, ec = run(ssh, f"cd {REMOTE_DIR}/extracted && zip -qr {REMOTE_OUTPUT} Payload/", 120)
    print(f"  done (exit={ec})")

    print("\n[6] 下载回本地 ...")
    sftp = ssh.open_sftp()
    sftp.get(REMOTE_OUTPUT, LOCAL_OUTPUT)
    sftp.close()
    size = os.path.getsize(LOCAL_OUTPUT)
    print(f"  [OK] {LOCAL_OUTPUT} ({size/1024/1024:.0f} MB)")

    ssh.exec_command(f"rm -rf {REMOTE_DIR}")
    ssh.close()
    print("\n完成! 用爱思助手签名后重试")


import shlex
if __name__ == "__main__":
    main()
