# MQTT username/password authentication validation (incl. 2K load test)
param(
    [string]$Region = "ap-south-1",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [string]$MqttUsername = $env:MQTT_USERNAME,
    [string]$MqttPassword = $env:MQTT_PASSWORD,
    [int]$Clients = 2000,
    [switch]$SkipLoad
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$coreIp = terraform output -raw emqx_core_public_ip
$mqttHost = terraform output -raw mqtt_nlb_dns_name

if (-not $MqttUsername) {
    try { $MqttUsername = terraform output -raw mqtt_auth_username } catch { $MqttUsername = "" }
}

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser `
    -MqttUsername $MqttUsername -MqttPassword $MqttPassword
Set-EmqxCredentialEnvironment -Credentials $creds
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername
$MqttUsername = $creds.MqttUsername
$MqttPassword = $creds.MqttPassword

if (-not (Test-EmqxCredentialsPresent -Credentials $creds)) {
    Write-Host "Dashboard password required (Secrets Manager, EMQX_DASHBOARD_PASSWORD, or terraform.tfvars)." -ForegroundColor Yellow
    exit 1
}
if ([string]::IsNullOrWhiteSpace($MqttUsername) -or [string]::IsNullOrWhiteSpace($MqttPassword)) {
    Write-Host "MQTT credentials required (Secrets Manager, env vars, or terraform.tfvars)." -ForegroundColor Yellow
    exit 1
}

Install-PythonRequirements -ProjectRoot $Root | Out-Null

$env:EMQX_CORE_IP = $coreIp
$env:MQTT_HOST = $mqttHost
$env:MQTT_USERNAME = $MqttUsername
$env:MQTT_PASSWORD = $MqttPassword
$env:EMQX_DASHBOARD_USERNAME = $DashboardUser
$env:EMQX_DASHBOARD_PASSWORD = $DashboardPassword
$env:AWS_REGION = $Region
$env:AUTH_LOAD_CLIENTS = "$Clients"

$argsList = @(
    (Join-MultiplePath @($Root, "scripts", "validate_authentication.py")),
    "--core-ip", $coreIp,
    "--mqtt-host", $mqttHost,
    "--mqtt-username", $MqttUsername,
    "--dashboard-user", $DashboardUser,
    "--clients", "$Clients"
)
if ($SkipLoad) { $argsList += "--skip-load" }

$exitCode = Invoke-ProjectPython -ProjectRoot $Root @argsList
exit $exitCode
