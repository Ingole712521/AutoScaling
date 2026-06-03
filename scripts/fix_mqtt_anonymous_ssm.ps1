param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$ids = aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Name,Values=${ProjectName}-core-1,${ProjectName}-replicant" `
              "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].InstanceId" --output text

if (-not $ids) { throw "No running EMQX instances." }

$cmdId = aws ssm send-command --region $Region `
    --document-name AWS-RunShellScript `
    --instance-ids $ids.Split() `
    --parameters file://"$Root/scripts/ssm-mqtt-patch.json" `
    --query Command.CommandId --output text

Write-Host "Patching MQTT auth on instances: $ids"
Start-Sleep -Seconds 15
foreach ($id in $ids.Split()) {
    aws ssm get-command-invocation --region $Region --command-id $cmdId --instance-id $id `
        --query StandardOutputContent --output text
}
Write-Host "Done. Run: .\scripts\prove_emqx_cluster.ps1"
