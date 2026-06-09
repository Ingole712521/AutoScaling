# AWS Secrets Manager helpers for EMQX credentials (used by validation/deploy scripts).

function Get-TerraformOutputRaw {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$ProjectRoot = "."
    )

    Push-Location $ProjectRoot
    try {
        $value = terraform output -raw $Name 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "null") { return $null }
        return $value.Trim()
    }
    finally {
        Pop-Location
    }
}

function Get-EmqxSecretsFromTfvars {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $result = @{
        DashboardUsername = "admin"
        DashboardPassword = ""
        MqttUsername      = ""
        MqttPassword      = ""
        NodeCookie        = ""
    }

    $tfvars = Join-Path $ProjectRoot "terraform.tfvars"
    if (-not (Test-Path $tfvars)) { return $result }

    $text = Get-Content -Raw $tfvars
    if ($text -match 'emqx_dashboard_username\s*=\s*"([^"]*)"') {
        $result.DashboardUsername = $Matches[1]
    }
    if ($text -match 'emqx_dashboard_password\s*=\s*"([^"]*)"') {
        $result.DashboardPassword = $Matches[1]
    }
    if ($text -match 'emqx_mqtt_username\s*=\s*"([^"]*)"') {
        $result.MqttUsername = $Matches[1]
    }
    if ($text -match 'emqx_mqtt_password\s*=\s*"([^"]*)"') {
        $result.MqttPassword = $Matches[1]
    }
    if ($text -match 'emqx_node_cookie\s*=\s*"([^"]*)"') {
        $result.NodeCookie = $Matches[1]
    }
    return $result
}

function Get-EmqxSecretsFromAws {
    param(
        [Parameter(Mandatory = $true)][string]$SecretName,
        [string]$Region = "ap-south-1"
    )

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI required to read Secrets Manager."
    }

    $json = aws secretsmanager get-secret-value `
        --region $Region `
        --secret-id $SecretName `
        --query SecretString `
        --output text 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        throw "Failed to read secret: $SecretName"
    }

    $obj = $json | ConvertFrom-Json
    return @{
        DashboardUsername = [string]$obj.dashboard_username
        DashboardPassword = [string]$obj.dashboard_password
        MqttUsername      = [string]$obj.mqtt_username
        MqttPassword      = [string]$obj.mqtt_password
        NodeCookie        = [string]$obj.node_cookie
    }
}

function Resolve-EmqxCredentials {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$Region = "ap-south-1",
        [string]$DashboardPassword = $env:EMQX_DASHBOARD_PASSWORD,
        [string]$DashboardUser = "",
        [string]$MqttUsername = $env:MQTT_USERNAME,
        [string]$MqttPassword = $env:MQTT_PASSWORD
    )

    $useSm = Get-TerraformOutputRaw -Name "use_secrets_manager" -ProjectRoot $ProjectRoot
    $secretName = Get-TerraformOutputRaw -Name "secrets_manager_secret_name" -ProjectRoot $ProjectRoot

    $creds = $null
    if ($useSm -eq "true" -and $secretName) {
        try {
            $creds = Get-EmqxSecretsFromAws -SecretName $secretName -Region $Region
            Write-Host "Credentials loaded from Secrets Manager: $secretName" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "Secrets Manager read failed ($($_.Exception.Message)); falling back to terraform.tfvars" -ForegroundColor Yellow
        }
    }

    if (-not $creds) {
        $creds = Get-EmqxSecretsFromTfvars -ProjectRoot $ProjectRoot
    }

    if ($DashboardPassword) { $creds.DashboardPassword = $DashboardPassword }
    if ($DashboardUser) { $creds.DashboardUsername = $DashboardUser }
    if ($MqttUsername) { $creds.MqttUsername = $MqttUsername }
    if ($MqttPassword) { $creds.MqttPassword = $MqttPassword }

    return $creds
}

function Set-EmqxCredentialEnvironment {
    param([Parameter(Mandatory = $true)][hashtable]$Credentials)

    if ($Credentials.DashboardUsername) {
        $env:EMQX_DASHBOARD_USERNAME = $Credentials.DashboardUsername
    }
    if ($Credentials.DashboardPassword) {
        $env:EMQX_DASHBOARD_PASSWORD = $Credentials.DashboardPassword
    }
    if ($Credentials.MqttUsername) {
        $env:MQTT_USERNAME = $Credentials.MqttUsername
    }
    if ($Credentials.MqttPassword) {
        $env:MQTT_PASSWORD = $Credentials.MqttPassword
    }
}

function Test-EmqxCredentialsPresent {
    param([Parameter(Mandatory = $true)][hashtable]$Credentials)

    return -not [string]::IsNullOrWhiteSpace($Credentials.DashboardPassword)
}
