# Apply fast cluster autoclean on running nodes (dashboard removes dead nodes in ~2m)
param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod",
    [string]$Autoclean = "2m"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$ids = aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Name,Values=${ProjectName}-core,${ProjectName}-replicant" `
              "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].InstanceId" --output text

if (-not $ids) { throw "No running EMQX instances." }

$commands = @(
    "set -euo pipefail",
    'ENV=/etc/emqx/terraform.env',
    'touch "$ENV"',
    "grep -q 'CLUSTER__AUTOCLEAN' `"`$ENV`" && sed -i '/CLUSTER__AUTOCLEAN/d' `"`$ENV`"",
    "echo 'EMQX_CLUSTER__AUTOCLEAN=$Autoclean' >> `"`$ENV`"",
    "grep -q 'CLUSTER__AUTOHEAL' `"`$ENV`" || echo 'EMQX_CLUSTER__AUTOHEAL=true' >> `"`$ENV`"",
    "systemctl daemon-reload",
    "systemctl restart emqx",
    "sleep 8",
    "echo CLUSTER_FAST_REFRESH_OK"
)

$params = @{ commands = $commands } | ConvertTo-Json -Compress -Depth 4
$paramFile = Join-Path $env:TEMP "ssm-cluster-fast-$(Get-Random).json"
$params | Set-Content -Encoding UTF8 $paramFile
$paramUri = ConvertTo-AwsFileUri -Path $paramFile

try {
    $cmdId = aws ssm send-command --region $Region `
        --document-name AWS-RunShellScript `
        --instance-ids $ids.Split() `
        --parameters $paramUri `
        --query Command.CommandId --output text

    Write-Host "Applying EMQX_CLUSTER__AUTOCLEAN=$Autoclean on: $ids"
    Start-Sleep -Seconds 15
    foreach ($id in $ids.Split()) {
        aws ssm get-command-invocation --region $Region --command-id $cmdId --instance-id $id `
            --query StandardOutputContent --output text
    }
    Write-Host "Done. Dead nodes disappear from dashboard within $Autoclean after scale-in."
    Write-Host "Live updates: ./scripts/watch_cluster_nodes.ps1"
}
finally {
    Remove-Item -Force $paramFile -ErrorAction SilentlyContinue
}
