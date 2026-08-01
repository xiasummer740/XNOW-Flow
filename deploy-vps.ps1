# 一键部署后端到 VPS
# 前提：代码已 push 到 GitHub，plink 会自动下载
# 密钥从 .env.local 读取（勿提交）

# 读取本地密钥
$envFile = Join-Path $PSScriptRoot ".env.local"
$hostkey = "ssh-rsa 3072 SHA256:0u8IYALIv+Qy8kQJTrbGjGUo+swtKcfKYwRN4TXewU0"
$password = ""
$vpsHost = "192.129.210.52"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^XNW_VPS_PASSWORD=(.*)$') { $password = $Matches[1] }
        if ($_ -match '^XNW_VPS_HOST=(.*)$') { $vpsHost = $Matches[1] }
    }
}
if (-not $password) {
    Write-Error "未找到 XNW_VPS_PASSWORD，请检查 .env.local"
    exit 1
}
$plink = "$env:TEMP\plink.exe"

# 下载 plink（如不存在）
if (-not (Test-Path $plink)) {
    Write-Host "Downloading plink..."
    Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe" -OutFile $plink -UseBasicParsing
}

Write-Host "=== Deploying to VPS ==="

$cmds = @(
    "set -e",
    "echo '--- git pull ---'",
    "cd /opt/xnow-flow-git && git pull origin main",
    "",
    "echo '--- copy files ---'",
    "cp -f backend/connection_manager.py /opt/xnow-flow/connection_manager.py",
    "cp -f backend/routers/ws.py /opt/xnow-flow/routers/ws.py",
    "cp -f backend/routers/device_commands.py /opt/xnow-flow/routers/device_commands.py",
    "",
    "echo '--- restart service ---'",
    "systemctl restart xnow-backend",
    "sleep 3",
    "",
    "echo '--- health check ---'",
    "curl -s http://127.0.0.1:8000/api/health",
    "echo ''",
    "systemctl is-active xnow-backend"
) -join "`n"

$output = & $plink -ssh -batch -pw $password -hostkey $hostkey root@$vpsHost $cmds 2>&1
Write-Host $output

Write-Host "=== Deploy complete ==="
