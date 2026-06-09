# Enable MQTT username/password auth on running instances (built-in database + user)
param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [string]$MqttUsername = $env:MQTT_USERNAME,
    [string]$MqttPassword = $env:MQTT_PASSWORD
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser `
    -MqttUsername $MqttUsername -MqttPassword $MqttPassword
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername
$MqttUsername = $creds.MqttUsername
$MqttPassword = $creds.MqttPassword

if ([string]::IsNullOrWhiteSpace($DashboardPassword) -or [string]::IsNullOrWhiteSpace($MqttUsername) -or [string]::IsNullOrWhiteSpace($MqttPassword)) {
    throw "Set dashboard + MQTT credentials via Secrets Manager, terraform.tfvars, or environment variables."
}

$ids = aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Name,Values=${ProjectName}-core,${ProjectName}-replicant" `
              "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].InstanceId" --output text

if (-not $ids) { throw "No running EMQX instances." }

$dashUserEsc = $DashboardUser -replace '\\', '\\\\' -replace '"', '\"'
$dashPassEsc = $DashboardPassword -replace '\\', '\\\\' -replace '"', '\"'
$mqttUserEsc = $MqttUsername -replace '\\', '\\\\' -replace '"', '\"'
$mqttPassEsc = $MqttPassword -replace '\\', '\\\\' -replace '"', '\"'

$commands = @(
    "set -euo pipefail",
    'ENV=/etc/emqx/terraform.env',
    'install -d /etc/systemd/system/emqx.service.d',
    "test -f /etc/systemd/system/emqx.service.d/terraform.conf || printf '%s\n' '[Service]' 'EnvironmentFile=-/etc/emqx/terraform.env' > /etc/systemd/system/emqx.service.d/terraform.conf",
    'touch "$ENV"',
    "grep -q 'ENABLE_AUTHN=true' `"`$ENV`" || { sed -i '/ENABLE_AUTHN=/d' `"`$ENV`"; echo 'EMQX_LISTENERS__TCP__DEFAULT__ENABLE_AUTHN=true' >> `"`$ENV`"; }",
    "grep -q 'AUTHENTICATION__1__MECHANISM' `"`$ENV`" || echo 'EMQX_AUTHENTICATION__1__MECHANISM=password_based' >> `"`$ENV`"",
    "grep -q 'AUTHENTICATION__1__BACKEND' `"`$ENV`" || echo 'EMQX_AUTHENTICATION__1__BACKEND=built_in_database' >> `"`$ENV`"",
    "grep -q 'AUTHENTICATION__1__ENABLE' `"`$ENV`" || echo 'EMQX_AUTHENTICATION__1__ENABLE=true' >> `"`$ENV`"",
    "grep -q 'MAX_PACKET_SIZE' `"`$ENV`" || echo 'EMQX_MQTT__MAX_PACKET_SIZE=1MB' >> `"`$ENV`"",
    "systemctl daemon-reload",
    "systemctl restart emqx",
    "sleep 12",
    "TOKEN=`$(curl -sf -X POST http://127.0.0.1:18083/api/v5/login -H 'Content-Type: application/json' -d `"{\`"username\`":\`"$dashUserEsc\`",\`"password\`":\`"$dashPassEsc\`"}`" | python3 -c `"import sys,json; print(json.load(sys.stdin).get('token',''))`")",
    'test -n "$TOKEN"',
    "curl -sf -X POST 'http://127.0.0.1:18083/api/v5/authentication/password_based%3Abuilt_in_database/users' -H `"Authorization: Bearer `$TOKEN`" -H 'Content-Type: application/json' -d `"{\`"user_id\`":\`"$mqttUserEsc\`",\`"password\`":\`"$mqttPassEsc\`"}`" || true",
    "ss -tln | grep ':1883'",
    "echo MQTT_AUTH_PATCH_OK"
)

$params = @{ commands = $commands } | ConvertTo-Json -Compress -Depth 4
$paramFile = Join-Path $env:TEMP "ssm-mqtt-auth-$(Get-Random).json"
$params | Set-Content -Encoding UTF8 $paramFile
$paramUri = ConvertTo-AwsFileUri -Path $paramFile

try {
    $cmdId = aws ssm send-command --region $Region `
        --document-name AWS-RunShellScript `
        --instance-ids $ids.Split() `
        --parameters $paramUri `
        --query Command.CommandId --output text

    Write-Host "Enabling MQTT auth on instances: $ids"
    Start-Sleep -Seconds 20
    foreach ($id in $ids.Split()) {
        aws ssm get-command-invocation --region $Region --command-id $cmdId --instance-id $id `
            --query StandardOutputContent --output text
    }
    Write-Host "Done. Run: ./scripts/validate_authentication.ps1"
}
finally {
    Remove-Item -Force $paramFile -ErrorAction SilentlyContinue
}
