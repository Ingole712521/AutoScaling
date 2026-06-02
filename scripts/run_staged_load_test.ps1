# Run staged MQTT load against EMQX NLB to trigger autoscaling.
# Usage:
#   .\scripts\run_staged_load_test.ps1
#   .\scripts\run_staged_load_test.ps1 -MqttHost "your-nlb.elb.amazonaws.com"
#   .\scripts\run_staged_load_test.ps1 -FromTerraform

param(
    [string]$MqttHost = $env:MQTT_HOST,
    [string]$TerraformDir = ".",
    [switch]$FromTerraform,
    [string]$PublishInterval = $env:PUBLISH_INTERVAL,
    [string]$PayloadSize = $env:PAYLOAD_SIZE,
    [string]$MessagesPerBurst = $env:MESSAGES_PER_BURST,
    [string]$LoadStages = $env:LOAD_STAGES
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if ($FromTerraform) {
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw "terraform is not installed or not on PATH."
    }
    Push-Location $TerraformDir
    try {
        foreach ($name in @("mqtt_nlb_dns_name", "nlb_dns_name")) {
            $value = terraform output -raw $name 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value)) {
                $MqttHost = $value
                break
            }
        }
    }
    finally {
        Pop-Location
    }
}

if ([string]::IsNullOrWhiteSpace($MqttHost)) {
    Write-Host "Set -MqttHost or MQTT_HOST, or use -FromTerraform after terraform apply."
    Write-Host "Example: .\scripts\run_staged_load_test.ps1 -FromTerraform"
    exit 1
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python 3 is required."
}

# Demo defaults: heavy load from stage 1 to trigger network/CPU thresholds quickly
if ([string]::IsNullOrWhiteSpace($PublishInterval)) { $PublishInterval = "0.001" }
if ([string]::IsNullOrWhiteSpace($PayloadSize)) { $PayloadSize = "16384" }
if ([string]::IsNullOrWhiteSpace($MessagesPerBurst)) { $MessagesPerBurst = "10" }
if ([string]::IsNullOrWhiteSpace($LoadStages)) {
    $LoadStages = "40:180:baseline-heavy,80:300:scale-out-2,120:300:scale-out-3,10:360:scale-in"
}

Write-Host "Installing load test dependencies..."
python -m pip install -q -r loadtest/requirements.txt

$env:PYTHONUNBUFFERED = "1"
$argsList = @(
    "-u", "loadtest/staged_load.py",
    "--host", $MqttHost,
    "--publish-interval", $PublishInterval,
    "--payload-size", $PayloadSize,
    "--messages-per-burst", $MessagesPerBurst,
    "--stages", $LoadStages
)

Write-Host "Running HIGH-INTENSITY load test against $MqttHost"
Write-Host "  publish-interval=$PublishInterval  payload-size=$PayloadSize  burst=$MessagesPerBurst"
python @argsList
