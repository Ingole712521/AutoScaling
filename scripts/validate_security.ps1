# Security validation: SG rules, ports 1883/8883/18083, TLS/ACM
param(
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "emqx-prod",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [string]$DashboardCidr = "",
    [string]$TlsHostname = $env:MQTT_TLS_HOSTNAME,
    [switch]$SkipReachability
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$coreIp = terraform output -raw emqx_core_public_ip
$mqttHost = terraform output -raw mqtt_nlb_dns_name
$nlbSg = terraform output -raw nlb_security_group_id
$nodesSg = terraform output -raw emqx_nodes_security_group_id

$tlsEnabled = $false
$acmArn = ""
try {
    $tlsEnabled = (terraform output -raw mqtt_tls_enabled) -eq "true"
    if ($tlsEnabled) {
        $acmArn = terraform output -raw acm_certificate_arn
    }
} catch {
    $tlsEnabled = $false
}

if (-not $DashboardCidr) {
    $tfvars = Join-Path $Root "terraform.tfvars"
    $DashboardCidr = "0.0.0.0/0"
    if (Test-Path $tfvars) {
        $tfvarsText = Get-Content -Raw $tfvars
        if ($tfvarsText -match 'dashboard_allowed_cidr\s*=\s*"([^"]*)"') {
            $DashboardCidr = $Matches[1]
        }
    }
}

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser
Set-EmqxCredentialEnvironment -Credentials $creds
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername

Install-PythonRequirements -ProjectRoot $Root | Out-Null

$env:EMQX_CORE_IP = $coreIp
$env:MQTT_HOST = $mqttHost
$env:NLB_SG_ID = $nlbSg
$env:EMQX_NODES_SG_ID = $nodesSg
$env:DASHBOARD_ALLOWED_CIDR = $DashboardCidr
$env:AWS_REGION = $Region
$env:PROJECT_NAME = $ProjectName
if ($DashboardPassword) { $env:EMQX_DASHBOARD_PASSWORD = $DashboardPassword }
$env:EMQX_DASHBOARD_USERNAME = $DashboardUser
$env:MQTT_TLS_ENABLED = $(if ($tlsEnabled) { "true" } else { "false" })
if ($acmArn) { $env:ACM_CERTIFICATE_ARN = $acmArn }
if ($TlsHostname) { $env:MQTT_TLS_HOSTNAME = $TlsHostname }

$argsList = @(
    (Join-MultiplePath @($Root, "scripts", "validate_security.py")),
    "--region", $Region,
    "--project", $ProjectName,
    "--core-ip", $coreIp,
    "--mqtt-host", $mqttHost,
    "--nlb-sg", $nlbSg,
    "--nodes-sg", $nodesSg,
    "--dashboard-cidr", $DashboardCidr,
    "--dashboard-user", $DashboardUser
)
if ($tlsEnabled) { $argsList += "--tls-enabled" }
if ($acmArn) { $argsList += @("--acm-arn", $acmArn) }
if ($TlsHostname) { $argsList += @("--tls-hostname", $TlsHostname) }
if ($SkipReachability) { $argsList += "--skip-reachability" }

$exitCode = Invoke-ProjectPython -ProjectRoot $Root @argsList
exit $exitCode
