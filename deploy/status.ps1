[CmdletBinding()]
param(
    [ValidateSet('Local', 'Intranet')][string]$Profile = 'Local',
    [string]$ServerHost
)

$ErrorActionPreference = 'Stop'
$suiteRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $configuration = Get-ChanSuiteConfiguration -SuiteRoot $suiteRoot
    $resolvedProfile = Resolve-ChanSuiteProfile -Profiles $configuration.Profiles -Profile $Profile -ServerHost $ServerHost
}
catch {
    Write-Host ("[ERROR] {0}" -f $_.Exception.Message)
    exit 1
}

Write-Host 'CHAN SUITE STATUS'
Write-Host ''
Write-Host ("Profile    : {0}" -f $resolvedProfile.Profile)
Write-Host ("Bind host  : {0}" -f $resolvedProfile.BindHost)
Write-Host ("Public host: {0}" -f $resolvedProfile.PublicHost)
Write-Host ''

foreach ($application in @($configuration.Applications)) {
    try {
        $applicationPath = Join-Path $suiteRoot $application.path
        Write-Host $application.name
        if (-not (Test-Path -LiteralPath $applicationPath -PathType Container)) {
            Write-Host '  directory : NOT FOUND'
            Write-Host ''
            continue
        }

        Write-Host '  directory : OK'
        $endpoints = @(
            [PSCustomObject]@{ Name = 'frontend'; Port = $application.frontendPort }
            [PSCustomObject]@{ Name = 'backend'; Port = $application.backendPort }
        )
        foreach ($endpoint in $endpoints) {
            if ($null -eq $endpoint.Port) {
                continue
            }
            $isRunning = Test-PortListening -Port $endpoint.Port
            $state = if ($isRunning) { 'RUNNING' } else { 'STOPPED' }
            Write-Host ("  {0,-10}: {1} {2}" -f $endpoint.Name, $endpoint.Port, $state)
            Write-Host ("  {0} url : {1}" -f $endpoint.Name, (Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $endpoint.Port))
            if ($Profile -eq 'Intranet' -and $isRunning -and (Test-PortLoopbackOnly -Port $endpoint.Port)) {
                Write-Host ("  [WARN] {0} is listening only on loopback; it may not be reachable from other PCs." -f $endpoint.Name)
            }
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
