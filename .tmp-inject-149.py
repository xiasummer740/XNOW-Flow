#!/usr/bin/env python3
"""一次性：149（A4 账号池同步 + open_tab 非 home 假成功修复）打包 TikTok_XNOW_v1.4.149_BH.ipa"""
import paramiko, os, sys

PROJECT = os.path.dirname(os.path.abspath(__file__))
env = {}
for line in open(os.path.join(PROJECT, '.env.local'), encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, _, v = line.partition('='); env[k.strip()] = v.strip()
PWD = env.get('XNW_VPS_PASSWORD', '')

LOCAL_DYLIB = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-149', 'xnower.dylib')
OUT = 'TikTok_XNOW_v1.4.149_BH.ipa'

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.129.210.52', 22, 'root', PWD, timeout=15)

def run(cmd, timeout=180):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    ec = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    tail = '\n'.join(out.strip().split('\n')[-12:])
    if tail.strip():
        print(f"  {tail}")
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-6:]:
            print(f"  ERR: {line}")
    return out, ec

print("[1] 上传 xnower.dylib + Config.plist → /root/xnow-build/ ...")
# Config.plist 必须与 dylib 同目录上传：vps-inject.py 靠它生成 xnower-config.plist 并
# 从输出文件名写 XNOWER_BuildVersion（2026-09-05 血证：149 只传 dylib → 版本沿用 base 148）
run("mkdir -p /root/xnow-build", 15)
sftp = ssh.open_sftp()
sftp.put(LOCAL_DYLIB, '/root/xnow-build/xnower-149.dylib')
sftp.put(os.path.join(PROJECT, 'ios-plugin', 'xnow-dylib', 'Config.plist'), '/root/xnow-build/Config.plist')
sftp.close()
print("  uploaded")

print("[2] 定位基础 IPA ...")
out, _ = run("ls -t /opt/xnow-flow/static/TikTok_XNOW_v1.4.14[0-9]_BH.ipa 2>/dev/null | head -1")
base_ipa = out.strip().split('\n')[0].strip() if out.strip() else None
if not base_ipa:
    print("❌ 未找到 base IPA"); ssh.close(); sys.exit(1)
print(f"  基础 IPA: {base_ipa}")

print(f"[3] vps-inject: → {OUT} ...")
run(f"cd /opt/xnow-flow && python3 vps-inject.py {base_ipa} /root/xnow-build/xnower-149.dylib /opt/xnow-flow/static/{OUT} 2>&1", 300)

print("[4] 验证（zip 完整性 + plist 版本号自检，版本不符即失败，不再静默收错包）...")
out, _ = run(f"ls -l /opt/xnow-flow/static/{OUT}")
out2, _ = run(f"python3 -c \"import zipfile,plistlib;cfg=plistlib.loads(zipfile.ZipFile('/opt/xnow-flow/static/{OUT}').read('Payload/TikTok.app/xnower-config.plist'));print('VERSION='+str(cfg.get('XNOWER_BuildVersion')))\"")
ver_ok = 'VERSION=1.4.149' in out2
ok = ver_ok
if not ver_ok:
    print(f"  ❌ plist 版本号异常（应为 1.4.149）：{out2.strip()[-100:] if out2.strip() else '无输出'}")

if ok:
    print("[5] 下载本地 ...")
    sftp = ssh.open_sftp()
    sftp.get(f'/opt/xnow-flow/static/{OUT}', os.path.join(PROJECT, OUT))
    sftp.close()
    sz = os.path.getsize(os.path.join(PROJECT, OUT))
    print(f"  ✅ {OUT} ({sz/1024/1024:.1f} MB)")
else:
    print("❌ 注入失败，未下载")

print("[6] 清理 VPS 临时构建残留（祥哥要求不占磁盘）...")
run(f"rm -rf /root/xnow-build/xnower-149.dylib", 30)
ssh.close()
print("=== Done ===")
