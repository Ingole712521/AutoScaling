# Cross-platform helpers for PowerShell Core (Windows, macOS, Linux).

function Test-TcpPortOpen {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = 5000
    )

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return $false
    }

    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect($HostName, $Port, $null, $null)
        $connected = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $connected) {
            return $false
        }
        $client.EndConnect($connect)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $client) {
            $client.Dispose()
        }
    }
}

function Get-PythonExecutable {
    foreach ($name in @("python3", "python")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }
    return $null
}

function Join-MultiplePath {
    param([Parameter(Mandatory = $true)][string[]]$Segments)

    $path = $Segments[0]
    for ($i = 1; $i -lt $Segments.Count; $i++) {
        $path = Join-Path $path $Segments[$i]
    }
    return $path
}

function Test-UseProjectVenv {
    if ($IsMacOS -or $IsLinux) {
        return $true
    }
    if ($null -ne $IsWindows) {
        return -not $IsWindows
    }
    return $env:OS -ne "Windows_NT"
}

function Get-ProjectVenvPython {
    param([string]$ProjectRoot)

    if (Test-UseProjectVenv) {
        return Join-MultiplePath @($ProjectRoot, ".venv", "bin", "python")
    }
    return Join-MultiplePath @($ProjectRoot, ".venv", "Scripts", "python.exe")
}

function Initialize-ProjectPython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $basePython = Get-PythonExecutable
    if (-not $basePython) {
        throw "Python 3 is required. Install python3 (macOS: brew install python) and retry."
    }

    $useVenv = Test-UseProjectVenv
    $venvPython = Get-ProjectVenvPython -ProjectRoot $ProjectRoot

    if ($useVenv -and -not (Test-Path $venvPython)) {
        Write-Host "Creating Python virtual environment at .venv (required on macOS/Linux)..."
        & $basePython -m venv (Join-Path $ProjectRoot ".venv")
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create .venv. Ensure python3-venv is installed (macOS: bundled with python.org installer; Linux: python3-venv package)."
        }
    }

    if ($useVenv) {
        return $venvPython
    }

    return $basePython
}

function Install-PythonRequirements {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$RequirementsFile = "loadtest/requirements.txt"
    )

    $python = Initialize-ProjectPython -ProjectRoot $ProjectRoot
    $reqPath = Join-Path $ProjectRoot $RequirementsFile
    & $python -m pip install -q -r $reqPath
    if ($LASTEXITCODE -ne 0) {
        throw "pip install failed for $RequirementsFile"
    }
    return $python
}

function Invoke-ProjectPython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$PythonArgs
    )

    $python = Initialize-ProjectPython -ProjectRoot $ProjectRoot
    & $python @PythonArgs
    return $LASTEXITCODE
}

function ConvertTo-AwsFileUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path $Path).Path -replace '\\', '/'
    return "file://$resolved"
}

function Open-UrlInBrowser {
    param([Parameter(Mandatory = $true)][string]$Url)

    if ($IsMacOS) {
        & open $Url
    }
    elseif ($IsLinux) {
        if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
            & xdg-open $Url
        }
        else {
            Write-Host "Open in browser: $Url"
        }
    }
    else {
        Start-Process $Url
    }
}

function Start-LoadTestInNewTerminal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$MqttHost
    )

    $loadScript = Join-MultiplePath @($ProjectRoot, "scripts", "run_staged_load_test.ps1")
    $escapedRoot = $ProjectRoot -replace "'", "''"

    if ($IsMacOS) {
        $inner = @"
cd '$escapedRoot'
`$env:PYTHONUNBUFFERED = '1'
`$env:PUBLISH_INTERVAL = '0.001'
`$env:PAYLOAD_SIZE = '16384'
`$env:MESSAGES_PER_BURST = '10'
`$env:LOAD_STAGES = '40:180:baseline-heavy,80:300:scale-out-2,120:300:scale-out-3,10:90:scale-in'
Write-Host 'Starting HIGH-INTENSITY autoscaling load test against $MqttHost' -ForegroundColor Green
& '$loadScript' -MqttHost '$MqttHost'
"@
        $escapedInner = $inner -replace '\\', '\\\\' -replace '"', '\"'
        & osascript -e "tell application `"Terminal`" to do script `"$escapedInner`""
        Write-Host "Load test started in a new Terminal window." -ForegroundColor Green
        return
    }

    if ($IsLinux -and (Get-Command gnome-terminal -ErrorAction SilentlyContinue)) {
        $cmd = "cd '$escapedRoot' && export PYTHONUNBUFFERED=1 PUBLISH_INTERVAL=0.001 PAYLOAD_SIZE=16384 MESSAGES_PER_BURST=10 LOAD_STAGES='40:180:baseline-heavy,80:300:scale-out-2,120:300:scale-out-3,10:90:scale-in' && pwsh -NoProfile -File '$loadScript' -MqttHost '$MqttHost'; exec bash"
        & gnome-terminal -- bash -lc $cmd
        Write-Host "Load test started in a new terminal." -ForegroundColor Green
        return
    }

    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $command = @"
Set-Location '$escapedRoot'
`$env:PYTHONUNBUFFERED = '1'
`$env:PUBLISH_INTERVAL = '0.001'
`$env:PAYLOAD_SIZE = '16384'
`$env:MESSAGES_PER_BURST = '10'
`$env:LOAD_STAGES = '40:180:baseline-heavy,80:300:scale-out-2,120:300:scale-out-3,10:90:scale-in'
Write-Host 'Starting HIGH-INTENSITY autoscaling load test against $MqttHost' -ForegroundColor Green
& '$loadScript' -MqttHost '$MqttHost'
"@
    Start-Process $shell -ArgumentList @("-NoExit", "-Command", $command)
    Write-Host "Load test started in a new PowerShell window." -ForegroundColor Green
}
