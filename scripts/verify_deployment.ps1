param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$coreIp = terraform output -raw emqx_core_public_ip
$mqttHost = terraform output -raw mqtt_nlb_dns_name
$dashboardUrl = terraform output -raw emqx_dashboard_url

Write-Host ""
Write-Host "=== EMQX Deployment Verification ===" -ForegroundColor Cyan
Write-Host "Dashboard: $dashboardUrl"
Write-Host "MQTT NLB:  tcp://${mqttHost}:1883"
Write-Host ""

$dashboard = Test-NetConnection -ComputerName $coreIp -Port 18083 -WarningAction SilentlyContinue
$mqtt = Test-NetConnection -ComputerName $mqttHost -Port 1883 -WarningAction SilentlyContinue

Write-Host ("Dashboard 18083: {0}" -f $(if ($dashboard.TcpTestSucceeded) { "PASS" } else { "FAIL" }))
Write-Host ("MQTT NLB 1883:   {0}" -f $(if ($mqtt.TcpTestSucceeded) { "PASS" } else { "FAIL" }))

if ($mqtt.TcpTestSucceeded -and (Get-Command python -ErrorAction SilentlyContinue)) {
    python -m pip install -q -r loadtest/requirements.txt 2>$null
    python scripts/mqtt_probe.py --host $mqttHost
}

if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "=== NLB target health ===" -ForegroundColor Cyan
    $arn = aws elbv2 describe-target-groups --region $Region --names "${ProjectName}-mqtt-tg" `
        --query "TargetGroups[0].TargetGroupArn" --output text 2>$null
    if ($arn -and $arn -ne "None") {
        aws elbv2 describe-target-health --region $Region --target-group-arn $arn `
            --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]" --output table
        $states = aws elbv2 describe-target-health --region $Region --target-group-arn $arn `
            --query "TargetHealthDescriptions[*].TargetHealth.State" --output text 2>$null
        if ($states -match "initial|draining") {
            Write-Host ""
            Write-Host "Note: MQTT via NLB fails until a target is 'healthy' (bootstrap ~5-15 min)." -ForegroundColor Yellow
            Write-Host "      Watch: .\scripts\watch_bootstrap.ps1" -ForegroundColor Yellow
        }
        if ($states -match "unhealthy") {
            Write-Host ""
            Write-Host "If unhealthy >10 min, check replicant: sudo tail -50 /var/log/emqx-bootstrap.log" -ForegroundColor Yellow
            Write-Host "      OSS 5.8+ must NOT set EMQX_NODE__ROLE=replicant (fixed in userdata)." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Full proof: .\scripts\prove_emqx_cluster.ps1" -ForegroundColor Cyan

if ($dashboard.TcpTestSucceeded -and $mqtt.TcpTestSucceeded) { exit 0 }
exit 1
