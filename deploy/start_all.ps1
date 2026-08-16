[CmdletBinding()]
param(
    [ValidateSet('Local', 'Intranet')][string]$Profile = 'Local',
    [string]$ServerHost
)

$ErrorActionPreference = 'Stop'
$suiteRoot = Split-Path -Parent $PSScriptRoot
$logsPath = Join-Path $suiteRoot 'logs'
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-ApplicationByName {
    param(
        [Parameter(Mandatory = $true)]$Applications,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $application = @($Applications | Where-Object { $_.name -eq $Name -and $_.enabled -eq $true }) | Select-Object -First 1
    if ($null -eq $application) {
        return $null
    }
    return $application
}

function Get-ApplicationPath {
    param([Parameter(Mandatory = $true)]$Application)
    return Join-Path $suiteRoot $Application.path
}

function Get-VenvPython {
    param([Parameter(Mandatory = $true)][string]$ApplicationPath)

    $candidates = @(
        (Join-Path $ApplicationPath '.venv\Scripts\python.exe'),
        (Join-Path $ApplicationPath '.venv\bin\python')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Copy-Environment {
    param([Parameter(Mandatory = $true)][hashtable]$Environment)

    $copy = @{}
    foreach ($keyName in $Environment.Keys) {
        $copy[$keyName] = $Environment[$keyName]
    }
    return $copy
}

function Start-ManagedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][hashtable]$Environment
    )

    $stdoutPath = Join-Path $logsPath ($Name + '.log')
    $stderrPath = Join-Path $logsPath ($Name + '.error.log')
    $savedEnvironment = @{}
    try {
        foreach ($keyName in $Environment.Keys) {
            $savedEnvironment[$keyName] = [Environment]::GetEnvironmentVariable($keyName, 'Process')
            [Environment]::SetEnvironmentVariable($keyName, [string]$Environment[$keyName], 'Process')
        }

        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru
        Write-Host ("[STARTED] {0}: PID {1}" -f $Name, $process.Id)
    }
    finally {
        foreach ($keyName in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($keyName, $savedEnvironment[$keyName], 'Process')
        }
    }
}

function Test-EndpointAvailableForStart {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Port
    )

    if (-not (Test-PortListening -Port $Port)) {
        return $true
    }

    Write-Host ("[RUNNING] {0}: port {1} is already in use" -f $Name, $Port)
    if ($Profile -eq 'Intranet' -and (Test-PortLoopbackOnly -Port $Port)) {
        Write-Host ("[WARN] {0} is listening only on loopback and may not be reachable from other PCs." -f $Name)
    }
    return $false
}

function Start-Frontend {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [Parameter(Mandatory = $true)][string]$PnpmPath
    )

    $name = $Application.name + '-frontend'
    $applicationPath = Get-ApplicationPath -Application $Application
    $workingDirectory = if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath -eq '.') {
        $applicationPath
    }
    else {
        Join-Path $applicationPath $RelativePath
    }

    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        Write-Host ("[SKIP] {0}: directory not found" -f $name)
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workingDirectory 'pnpm-lock.yaml') -PathType Leaf)) {
        throw "${name}: pnpm-lock.yaml was not found. Run setup_all.bat first."
    }

    $port = [int]$Application.frontendPort
    if (-not (Test-EndpointAvailableForStart -Name $name -Port $port)) {
        return
    }

    Start-ManagedProcess -Name $name -FilePath $PnpmPath `
        -ArgumentList @('run', 'dev', '--', '--host', $resolvedProfile.BindHost, '--port', [string]$port, '--strictPort') `
        -WorkingDirectory $workingDirectory -Environment $Environment
}

function Start-Backend {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)][string[]]$UvicornArguments,
        [Parameter(Mandatory = $true)][hashtable]$Environment
    )

    $name = $Application.name + '-backend'
    $applicationPath = Get-ApplicationPath -Application $Application
    if (-not (Test-Path -LiteralPath $applicationPath -PathType Container)) {
        Write-Host ("[SKIP] {0}: directory not found" -f $name)
        return
    }

    $pythonPath = Get-VenvPython -ApplicationPath $applicationPath
    if ($null -eq $pythonPath) {
        throw "${name}: .venv Python was not found. Run setup_all.bat first."
    }

    $port = [int]$Application.backendPort
    if (-not (Test-EndpointAvailableForStart -Name $name -Port $port)) {
        return
    }

    $arguments = @('-m', 'uvicorn') + $UvicornArguments + @('--host', $resolvedProfile.BindHost, '--port', [string]$port)
    Start-ManagedProcess -Name $name -FilePath $pythonPath -ArgumentList $arguments `
        -WorkingDirectory $applicationPath -Environment $Environment
}

try {
    $configuration = Get-ChanSuiteConfiguration -SuiteRoot $suiteRoot
    $resolvedProfile = Resolve-ChanSuiteProfile -Profiles $configuration.Profiles -Profile $Profile -ServerHost $ServerHost
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null

    $pnpmCommand = Get-Command 'pnpm.cmd' -ErrorAction SilentlyContinue
    if ($null -eq $pnpmCommand) {
        $pnpmCommand = Get-Command 'pnpm' -ErrorAction SilentlyContinue
    }
    if ($null -eq $pnpmCommand) {
        throw 'pnpm was not found on PATH. Run setup_all.bat after installing pnpm.'
    }
    $pnpmPath = $pnpmCommand.Source
}
catch {
    Write-Host ("[ERROR] {0}" -f $_.Exception.Message)
    exit 1
}

Write-Host ("[PROFILE] {0}; bind host: {1}; public host: {2}" -f $resolvedProfile.Profile, $resolvedProfile.BindHost, $resolvedProfile.PublicHost)

$portal = Get-ApplicationByName -Applications $configuration.Applications -Name 'chan-portal'
$bochan = Get-ApplicationByName -Applications $configuration.Applications -Name 'bochan'
$malchan = Get-ApplicationByName -Applications $configuration.Applications -Name 'malchan'
$cauchan = Get-ApplicationByName -Applications $configuration.Applications -Name 'cauchan'
$dchan = Get-ApplicationByName -Applications $configuration.Applications -Name 'dchan'

try {
    if ($null -ne $portal) {
        $portalEnvironment = Get-ApplicationEnvironment -Application $portal -ResolvedProfile $resolvedProfile
        $portalLinks = Get-PortalEnvironment -Applications $configuration.Applications -PublicHost $resolvedProfile.PublicHost
        foreach ($keyName in $portalLinks.Keys) {
            $portalEnvironment[$keyName] = $portalLinks[$keyName]
        }
        Start-Frontend -Application $portal -RelativePath '.' -Environment $portalEnvironment -PnpmPath $pnpmPath
    }

    if ($null -ne $bochan) {
        $backendEnvironment = Get-ApplicationEnvironment -Application $bochan -ResolvedProfile $resolvedProfile
        $backendEnvironment['PYTHONUNBUFFERED'] = '1'
        Start-Backend -Application $bochan `
            -UvicornArguments @('bochan.serving.webapp.app:app') `
            -Environment $backendEnvironment

        $frontendEnvironment = Copy-Environment -Environment $backendEnvironment
        $frontendEnvironment['VITE_API_BASE'] = '/api/v1'
        Start-Frontend -Application $bochan -RelativePath 'web' -Environment $frontendEnvironment -PnpmPath $pnpmPath
    }

    if ($null -ne $malchan) {
        $backendEnvironment = Get-ApplicationEnvironment -Application $malchan -ResolvedProfile $resolvedProfile
        $backendEnvironment['PYTHONUNBUFFERED'] = '1'
        $backendEnvironment['MALCHAN_CORS_ORIGINS'] = "http://$($resolvedProfile.PublicHost):$($malchan.frontendPort),http://127.0.0.1:$($malchan.frontendPort),http://localhost:$($malchan.frontendPort)"
        Start-Backend -Application $malchan `
            -UvicornArguments @('malchan.app:create_app', '--factory') `
            -Environment $backendEnvironment

        $frontendEnvironment = Copy-Environment -Environment $backendEnvironment
        $frontendEnvironment['VITE_API_BASE'] = "http://$($resolvedProfile.PublicHost):$($malchan.backendPort)/api"
        Start-Frontend -Application $malchan -RelativePath 'frontend' -Environment $frontendEnvironment -PnpmPath $pnpmPath
    }

    if ($null -ne $cauchan) {
        $backendEnvironment = Get-ApplicationEnvironment -Application $cauchan -ResolvedProfile $resolvedProfile
        $backendEnvironment['PYTHONUNBUFFERED'] = '1'
        $backendEnvironment['CAUCHAN_CORS_ORIGINS'] = "http://$($resolvedProfile.PublicHost):$($cauchan.frontendPort),http://127.0.0.1:$($cauchan.frontendPort),http://localhost:$($cauchan.frontendPort)"
        Start-Backend -Application $cauchan `
            -UvicornArguments @('cauchan.api.app:app', '--app-dir', 'src') `
            -Environment $backendEnvironment

        $frontendEnvironment = Copy-Environment -Environment $backendEnvironment
        $frontendEnvironment['VITE_API_BASE_URL'] = "http://$($resolvedProfile.PublicHost):$($cauchan.backendPort)/api/v1"
        Start-Frontend -Application $cauchan -RelativePath 'web' -Environment $frontendEnvironment -PnpmPath $pnpmPath
    }

    if ($null -ne $dchan) {
        $backendEnvironment = Get-ApplicationEnvironment -Application $dchan -ResolvedProfile $resolvedProfile
        $backendEnvironment['PYTHONUNBUFFERED'] = '1'
        $backendEnvironment['DCHAN_CORS_ORIGINS'] = "http://$($resolvedProfile.PublicHost):$($dchan.frontendPort),http://127.0.0.1:$($dchan.frontendPort),http://localhost:$($dchan.frontendPort)"
        Start-Backend -Application $dchan `
            -UvicornArguments @('application.main:app') `
            -Environment $backendEnvironment

        $frontendEnvironment = Copy-Environment -Environment $backendEnvironment
        $frontendEnvironment['VITE_API_URL'] = "http://$($resolvedProfile.PublicHost):$($dchan.backendPort)"
        Start-Frontend -Application $dchan -RelativePath 'frontend' -Environment $frontendEnvironment -PnpmPath $pnpmPath
    }
}
catch {
    Write-Host ("[ERROR] Startup failed: {0}" -f $_.Exception.Message)
    exit 1
}

Write-Host ''
if ($null -ne $portal) {
    Write-Host ("Portal : {0}" -f (Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $portal.frontendPort))
}
if ($null -ne $bochan) {
    Write-Host ("bochan : {0}" -f (Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $bochan.frontendPort))
}
if ($null -ne $malchan) {
    Write-Host ("malchan: {0}" -f (Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $malchan.frontendPort))
}
if ($null -ne $cauchan) {
    Write-Host ("cauchan: {0}" -f (Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $cauchan.frontendPort))
}
if ($null -ne $dchan) {
    Write-Host ("dchan  : {0}" -f (Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $dchan.frontendPort))
}
Write-Host ("Logs   : {0}" -f $logsPath)
Write-Host '[OK] Launch commands were issued for all enabled applications.'
