# Run all validation in one go: verify → security → auth → auth scale-out → optional 2K load
param(
    [string]$Region = "ap-south-1",
    [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
    [string]$DashboardUser = "admin",
    [int]$AuthLoadClients = 2000,
    [switch]$SkipVerify,
    [switch]$SkipSecurity,
    [switch]$Skip2K,
    [switch]$SkipScaleOut
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path (Join-Path $PSScriptRoot "lib") "PlatformHelpers.ps1")

$creds = Resolve-EmqxCredentials -ProjectRoot $Root -Region $Region `
    -DashboardPassword $DashboardPassword -DashboardUser $DashboardUser
Set-EmqxCredentialEnvironment -Credentials $creds
$DashboardPassword = $creds.DashboardPassword
$DashboardUser = $creds.DashboardUsername

function Invoke-Step {
    param(
        [string]$Title,
        [scriptblock]$Action
    )
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed: $Title (exit $LASTEXITCODE)"
    }
}

Write-Host ""
Write-Host "EMQX FULL VALIDATION SUITE (single run)" -ForegroundColor Green
Write-Host "Core + replicant ASGs | security | auth | scale-out auth" -ForegroundColor Green

try {
    if (-not $SkipVerify) {
        Invoke-Step "Step 1/5 — Deployment verify" {
            & (Join-Path $PSScriptRoot "verify_deployment.ps1") -Region $Region
        }
    }

    if (-not $SkipSecurity) {
        Invoke-Step "Step 2/5 — Security validation" {
            $secArgs = @{ Region = $Region; DashboardUser = $DashboardUser }
            if ($DashboardPassword) { $secArgs.DashboardPassword = $DashboardPassword }
            & (Join-Path $PSScriptRoot "validate_security.ps1") @secArgs
        }
    }

    Invoke-Step "Step 3/5 — Authentication checks (no 2K yet)" {
        $authArgs = @{ Region = $Region; DashboardUser = $DashboardUser; SkipLoad = $true }
        if ($DashboardPassword) { $authArgs.DashboardPassword = $DashboardPassword }
        & (Join-Path $PSScriptRoot "validate_authentication.ps1") @authArgs
    }

    if (-not $SkipScaleOut) {
        Invoke-Step "Step 4/5 — Authentication during scale-out (core + replicant ASGs)" {
            $scaleArgs = @{ Region = $Region; DashboardUser = $DashboardUser }
            if ($DashboardPassword) { $scaleArgs.DashboardPassword = $DashboardPassword }
            & (Join-Path $PSScriptRoot "validate_auth_scale_out.ps1") @scaleArgs
        }
    }

    if (-not $Skip2K) {
        Invoke-Step "Step 5/5 — Authentication under load ($AuthLoadClients clients)" {
            $loadArgs = @{
                Region = $Region
                DashboardUser = $DashboardUser
                Clients = $AuthLoadClients
            }
            if ($DashboardPassword) { $loadArgs.DashboardPassword = $DashboardPassword }
            & (Join-Path $PSScriptRoot "validate_authentication.ps1") @loadArgs
        }
    }

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "=== FULL VALIDATION SUITE: ALL STEPS PASSED ===" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "=== FULL VALIDATION SUITE: FAILED ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
