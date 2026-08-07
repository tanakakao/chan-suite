[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$suiteRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $suiteRoot 'config/apps.json'

function Test-PortListening {
    <#
    Tests whether a local TCP port is listening.

    Args:
        Port: TCP port number to inspect.

    Returns:
        Boolean indicating whether a listener exists.
    #>
    param([Parameter(Mandatory = $true)][int]$Port)

    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return ($null -ne ($listeners | Where-Object { $_.Port -eq $Port } | Select-Object -First 1))
}

try {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Write-Error ("Failed to read configuration '{0}': {1}" -f $configPath, $_.Exception.Message)
    exit 1
}

Write-Host 'CHAN SUITE STATUS'
Write-Host ''

foreach ($application in @($config.applications)) {
    try {
        $applicationPath = Join-Path $suiteRoot $application.path
        Write-Host $application.name
        if (-not (Test-Path -LiteralPath $applicationPath -PathType Container)) {
            Write-Host '  directory : NOT FOUND'
            Write-Host ''
            continue
        }

        Write-Host '  directory : OK'
        if ($null -ne $application.frontendPort) {
            $state = if (Test-PortListening -Port $application.frontendPort) { 'RUNNING' } else { 'STOPPED' }
            Write-Host ("  frontend  : {0} {1}" -f $application.frontendPort, $state)
        }
        if ($null -ne $application.backendPort) {
            $state = if (Test-PortListening -Port $application.backendPort) { 'RUNNING' } else { 'STOPPED' }
            Write-Host ("  backend   : {0} {1}" -f $application.backendPort, $state)
        }
        if ($application.enabled -ne $true) {
            Write-Host '  enabled   : false'
        }
        Write-Host ''
    }
    catch {
        Write-Warning ("{0}: status check failed: {1}" -f $application.name, $_.Exception.Message)
        Write-Host ''
    }
}
