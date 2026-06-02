param(
    [string]$HostName,
    [int]$Port,
    [int]$TimeoutSec = 900,
    [int]$IntervalSec = 15
)

$ErrorActionPreference = "Stop"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$attempt = 0

Write-Host "Waiting for ${HostName}:${Port} (timeout ${TimeoutSec}s)..."

while ((Get-Date) -lt $deadline) {
    $attempt++
    $result = Test-NetConnection -ComputerName $HostName -Port $Port -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host "Port ${Port} is open on ${HostName} (attempt ${attempt})."
        return $true
    }

    $remaining = [int]($deadline - (Get-Date)).TotalSeconds
    Write-Host "  attempt ${attempt}: not ready yet (${remaining}s remaining)..."
    Start-Sleep -Seconds $IntervalSec
}

Write-Host "Timed out waiting for ${HostName}:${Port}" -ForegroundColor Red
return $false
