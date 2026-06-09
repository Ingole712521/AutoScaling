# Live cluster node watcher (API updates faster than dashboard UI auto-refresh)
param(
    [string]$Region = "ap-south-1",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [double]$IntervalSec = 5,
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$coreIp = terraform output -raw emqx_core_public_ip

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser
Set-EmqxCredentialEnvironment -Credentials $creds
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername

if (-not (Test-EmqxCredentialsPresent -Credentials $creds)) {
    Write-Host "Set EMQX_DASHBOARD_PASSWORD, use Secrets Manager, or add emqx_dashboard_password to terraform.tfvars" -ForegroundColor Yellow
    exit 1
}

Install-PythonRequirements -ProjectRoot $Root | Out-Null

$env:EMQX_CORE_IP = $coreIp
$env:EMQX_DASHBOARD_USERNAME = $DashboardUser
$env:EMQX_DASHBOARD_PASSWORD = $DashboardPassword

$argsList = @(
    (Join-MultiplePath @($Root, "scripts", "watch_cluster_nodes.py")),
    "--core-ip", $coreIp,
    "--user", $DashboardUser,
    "--interval-sec", "$IntervalSec"
)
if ($Once) { $argsList += "--once" }

$exitCode = Invoke-ProjectPython -ProjectRoot $Root @argsList
exit $exitCode
