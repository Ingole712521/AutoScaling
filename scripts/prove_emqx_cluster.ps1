# Full proof: cluster + NLB + MQTT load spread + ASG
param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [int]$LoadClients = 30,
    [switch]$SkipLoad
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$coreIp = terraform output -raw emqx_core_public_ip
$mqttHost = terraform output -raw mqtt_nlb_dns_name
$asgName = terraform output -raw replicant_asg_name

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser
Set-EmqxCredentialEnvironment -Credentials $creds
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername

if (-not (Test-EmqxCredentialsPresent -Credentials $creds)) {
    Write-Host "Password required. Use one of:" -ForegroundColor Yellow
    Write-Host "  AWS Secrets Manager (use_secrets_manager=true + terraform apply)"
    Write-Host '  $env:EMQX_DASHBOARD_PASSWORD = "your-password"'
    Write-Host '  ./scripts/prove_emqx_cluster.ps1 -DashboardPassword "your-password"'
    exit 1
}

Install-PythonRequirements -ProjectRoot $Root | Out-Null

$env:EMQX_CORE_IP = $coreIp
$env:MQTT_HOST = $mqttHost
$env:ASG_NAME = $asgName
$env:AWS_REGION = $Region
$env:PROJECT_NAME = $ProjectName

$argsList = @(
    (Join-MultiplePath @($Root, "scripts", "prove_emqx_cluster.py")),
    "--region", $Region,
    "--project", $ProjectName,
    "--core-ip", $coreIp,
    "--mqtt-host", $mqttHost,
    "--asg-name", $asgName,
    "--dashboard-user", $DashboardUser,
    "--load-clients", "$LoadClients"
)
if ($SkipLoad) { $argsList += "--skip-load" }

$exitCode = Invoke-ProjectPython -ProjectRoot $Root @argsList
exit $exitCode
