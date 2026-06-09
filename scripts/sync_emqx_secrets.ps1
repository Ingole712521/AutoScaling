# Push credentials from terraform.tfvars into AWS Secrets Manager (after password rotation)
param(
    [string]$Region = "ap-south-1",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
Set-Location $ProjectRoot
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$secretName = Get-TerraformOutputRaw -Name "secrets_manager_secret_name" -ProjectRoot $ProjectRoot
if (-not $secretName) {
    Write-Host "Secrets Manager not enabled (use_secrets_manager=false) or stack not applied." -ForegroundColor Yellow
    exit 1
}

$creds = Get-EmqxSecretsFromTfvars -ProjectRoot $ProjectRoot
if ([string]::IsNullOrWhiteSpace($creds.DashboardPassword) -or [string]::IsNullOrWhiteSpace($creds.NodeCookie)) {
    Write-Host "terraform.tfvars must contain emqx_dashboard_password and emqx_node_cookie for sync." -ForegroundColor Yellow
    exit 1
}

$payload = @{
    node_cookie        = $creds.NodeCookie
    dashboard_username = $creds.DashboardUsername
    dashboard_password = $creds.DashboardPassword
    mqtt_username      = $creds.MqttUsername
    mqtt_password      = $creds.MqttPassword
    mqtt_enable_authn  = $true
} | ConvertTo-Json -Compress

aws secretsmanager put-secret-value `
    --region $Region `
    --secret-id $secretName `
    --secret-string $payload

Write-Host "Updated secret: $secretName"
Write-Host "Run instance refresh or replace nodes so new launches load updated credentials."
