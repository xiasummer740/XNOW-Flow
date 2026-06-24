#!/usr/bin/env python3
"""Upload IPA to VPS and prepare for injection"""
import paramiko, os, sys

HOST = "192.129.210.52"
USER = "root"
PASSWORD = "0ISvaWdV88lLq871Re"
LOCAL_IPA = r"F:\summer\vs-code\XNOW-Flow\TikTok_42.2.0_BH.ipa"
REMOTE_PATH = "/opt/xnow-flow/TikTok_42.2.0_BH.ipa"

if not os.path.exists(LOCAL_IPA):
    print(f"File not found: {LOCAL_IPA}")
    sys.exit(1)

size = os.path.getsize(LOCAL_IPA)
print(f"File size: {size:,} bytes ({size/1024/1024:.1f} MB)")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, 22, USER, PASSWORD, timeout=30)

sftp = ssh.open_sftp()
print("Uploading...")
sftp.put(LOCAL_IPA, REMOTE_PATH, callback=lambda x,y: print(f"  {x*100//y}%", end="\r"))
sftp.close()

# Verify
stdin, stdout, stderr = ssh.exec_command(f"ls -lh {REMOTE_PATH} && file {REMOTE_PATH}")
print(f"\n{stdout.read().decode().strip()}")

# Show IPA info
stdin, stdout, stderr = ssh.exec_command(
    f"cd /opt/xnow-flow && unzip -l {REMOTE_PATH} 2>/dev/null | head -10 || "
    f"echo 'Not a valid zip/IPA'"
)
print(stdout.read().decode().strip()[:500])

ssh.close()
print("\nDone!")
