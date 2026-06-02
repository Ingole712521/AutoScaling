# Waits for EMQX bootstrap logs + ports, then runs load test.

param(
    [string]$TerraformDir = "."
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
& "$Root/scripts/deploy_and_load_test.ps1" -SkipApply -TerraformDir $TerraformDir
