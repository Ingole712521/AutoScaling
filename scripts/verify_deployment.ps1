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
Write-Host "Dashboard URL: $dashboardUrl"
Write-Host "MQTT NLB:      tcp://${mqttHost}:1883"
Write-Host ""

$dashboard = Test-NetConnection -ComputerName $coreIp -Port 18083 -WarningAction SilentlyContinue
$mqtt = Test-NetConnection -ComputerName $mqttHost -Port 1883 -WarningAction SilentlyContinue

Write-Host ("Dashboard port 18083: {0}" -f $(if ($dashboard.TcpTestSucceeded) { "PASS" } else { "FAIL" }))
Write-Host ("MQTT NLB port 1883:   {0}" -f $(if ($mqtt.TcpTestSucceeded) { "PASS" } else { "FAIL" }))

$clusterOk = $false
$emqxRunning = $false

if (Get-Command aws -ErrorAction SilentlyContinue) {
    $coreId = aws ec2 describe-instances `
        --region $Region `
        --filters "Name=ip-address,Values=$coreIp" "Name=instance-state-name,Values=running" `
        --query "Reservations[0].Instances[0].InstanceId" `
        --output text 2>$null

    if (-not $coreId -or $coreId -eq "None") {
        $coreId = aws ec2 describe-instances `
            --region $Region `
            --filters "Name=tag:Name,Values=${ProjectName}-core-1" "Name=instance-state-name,Values=running" `
            --query "Reservations[0].Instances[0].InstanceId" `
            --output text
    }

    if ($coreId -and $coreId -ne "None") {
        $cmd = aws ssm send-command `
            --region $Region `
            --document-name AWS-RunShellScript `
            --instance-ids $coreId `
            --parameters file://"$Root/scripts/ssm-verify.json" `
            --query Command.CommandId `
            --output text

        Start-Sleep -Seconds 6
        $output = aws ssm get-command-invocation `
            --region $Region `
            --command-id $cmd `
            --instance-id $coreId `
            --query StandardOutputContent `
            --output text

        Write-Host ""
        Write-Host "=== Core bootstrap / cluster checks (SSM) ===" -ForegroundColor Cyan
        Write-Host $output

        $emqxRunning = $output -match "is started"
        $clusterOk = $output -match "running_nodes" -and $output -match "emqx@"

        $nodeCount = ([regex]::Matches($output, "emqx@")).Count
        if ($nodeCount -ge 2) {
            Write-Host ""
            Write-Host ("Cluster nodes detected: {0} (core + replicants)" -f $nodeCount) -ForegroundColor Green
            $clusterOk = $true
        }

        if ($output -match "BOOTSTRAP_OK") {
            Write-Host "Bootstrap marker: PASS" -ForegroundColor Green
        } elseif ($emqxRunning -and $clusterOk) {
            Write-Host "Bootstrap marker: pending (EMQX running and cluster formed — OK)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if ($dashboard.TcpTestSucceeded -and $mqtt.TcpTestSucceeded -and $emqxRunning -and $clusterOk) {
    Write-Host "All checks passed. Deployment is healthy." -ForegroundColor Green
    exit 0
}

if ($dashboard.TcpTestSucceeded -and $mqtt.TcpTestSucceeded) {
    Write-Host "External ports open. EMQX/cluster SSM checks incomplete — re-run in 1-2 minutes." -ForegroundColor Yellow
    exit 0
}

Write-Host "Some checks failed. Run scripts/watch_bootstrap.ps1" -ForegroundColor Yellow
exit 1
