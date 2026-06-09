# Validate MQTT authentication during ASG scale-out
param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [string]$MqttUsername = $env:MQTT_USERNAME,
    [string]$MqttPassword = $env:MQTT_PASSWORD,
    [int]$BaselineClients = 50,
    [int]$LoadClients = 100,
    [int]$TargetAsgCapacity = 2,
    [int]$NewNodeProbes = 30
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$coreIp = terraform output -raw emqx_core_public_ip
$mqttHost = terraform output -raw mqtt_nlb_dns_name
$asgName = terraform output -raw replicant_asg_name
$coreAsgName = terraform output -raw core_asg_name

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser `
    -MqttUsername $MqttUsername -MqttPassword $MqttPassword
Set-EmqxCredentialEnvironment -Credentials $creds
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername
$MqttUsername = $creds.MqttUsername
$MqttPassword = $creds.MqttPassword

if ([string]::IsNullOrWhiteSpace($MqttUsername) -or [string]::IsNullOrWhiteSpace($MqttPassword)) {
    Write-Host "MQTT credentials required (Secrets Manager, env vars, or terraform.tfvars)." -ForegroundColor Yellow
    exit 1
}

Install-PythonRequirements -ProjectRoot $Root | Out-Null

$env:EMQX_CORE_IP = $coreIp
$env:MQTT_HOST = $mqttHost
$env:MQTT_USERNAME = $MqttUsername
$env:MQTT_PASSWORD = $MqttPassword
$env:ASG_NAME = $asgName
$env:CORE_ASG_NAME = $coreAsgName
$env:EMQX_DASHBOARD_USERNAME = $DashboardUser
$env:EMQX_DASHBOARD_PASSWORD = $DashboardPassword
$env:AWS_REGION = $Region
$env:PROJECT_NAME = $ProjectName

$argsList = @(
    (Join-MultiplePath @($Root, "scripts", "validate_auth_scale_out.py")),
    "--core-ip", $coreIp,
    "--mqtt-host", $mqttHost,
    "--mqtt-username", $MqttUsername,
    "--asg-name", $asgName,
    "--core-asg-name", $coreAsgName,
    "--project", $ProjectName,
    "--dashboard-user", $DashboardUser,
    "--baseline-clients", "$BaselineClients",
    "--load-clients", "$LoadClients",
    "--target-asg-capacity", "$TargetAsgCapacity",
    "--new-node-probes", "$NewNodeProbes"
)

$exitCode = Invoke-ProjectPython -ProjectRoot $Root @argsList
exit $exitCode
