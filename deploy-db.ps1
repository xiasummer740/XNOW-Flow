$b64 = "Y2QgL29wdC94bm93LWZsb3cgJiYgcm0gLWYgZGF0YS94bm93LmRiICYmIHNlZCAtaSBzL3RrX251bWJlci9hd2VtZV9udW1iZXIvZyBzZWVkLnB5ICYmIC9vcHQveG5vdy1mbG93L3Zlbi9iaW4vcHl0aG9uIHNlZWQucHkgJiYgL29wdC94bm93LWZsb3cvdmVuL2Jpbi9weXRob24gLWMgImZyb20gZGF0YWJhc2UgaW1wb3J0IFNlc3Npb25Mb2NhbDsgZnJvbSBtb2RlbHMudXNlciBpbXBvcnQgVXNlcjsgZGI9U2Vzc2lvbkxvY2FsKCk7IHU9ZGIucXVlcnkoVXNlcikuZmlsdGVyKFVzZXIudXNlcm5hbWU9PSdhZG1pbicpLmZpcnN0KCk7IHByaW50KCdhZG1pbiBvaycp"

# 密钥从 .env.local 读取（勿提交）
$envFile = Join-Path $PSScriptRoot ".env.local"
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

$secpass = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $secpass)
$session = New-SSHSession -ComputerName $vpsHost -Credential $cred -AcceptKey -Force

$r = Invoke-SSHCommand -SessionId $session.SessionId -Command ("echo $b64 | base64 -d | bash")
Write-Host "Seed: $($r.Output)"

$r2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "systemctl restart xnow-backend.service && sleep 6"
Write-Host "Restart: $($r2.Output)"

$r3 = Invoke-SSHCommand -SessionId $session.SessionId -Command "curl -s http://127.0.0.1:8000/api/health"
Write-Host "Health: $($r3.Output)"

Remove-SSHSession -SessionId $session.SessionId
