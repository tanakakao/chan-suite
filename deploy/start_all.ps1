[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$suiteRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $suiteRoot 'config/apps.json'
$logsPath = Join-Path $suiteRoot 'logs'

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

function Find-StartupScript {
    <#
    Finds a supported startup script in an application root.

    Args:
        ApplicationPath: Absolute path to the application directory.

    Returns:
        FileInfo for the highest-priority script, or null when none exists.
    #>
    param([Parameter(Mandatory = $true)][string]$ApplicationPath)

    $candidates = @('start_app.bat', 'start_web.bat', 'start.bat', 'start_app.ps1', 'start_web.ps1', 'start.ps1')
    foreach ($candidate in $candidates) {
        $candidatePath = Join-Path $ApplicationPath $candidate
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return Get-Item -LiteralPath $candidatePath
        }
    }
    return $null
}

function Start-ApplicationScript {
    <#
    Starts one discovered application script without changing the application.

    Args:
        Application: Application configuration object.
        ApplicationPath: Absolute path to the application directory.
        StartupScript: Startup script selected by Find-StartupScript.

    Returns:
        None.
    #>
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)][string]$ApplicationPath,
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$StartupScript
    )

    $stdoutPath = Join-Path $logsPath ($Application.name + '.log')
    $stderrPath = Join-Path $logsPath ($Application.name + '.error.log')
    if ($StartupScript.Extension -ieq '.bat') {
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', ('call "{0}"' -f $StartupScript.FullName)) `
            -WorkingDirectory $ApplicationPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    }
    else {
        $quotedScriptPath = ('"{0}"' -f $StartupScript.FullName)
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedScriptPath) `
            -WorkingDirectory $ApplicationPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    }
    Write-Host ("[STARTED] {0}: {1} (launcher PID {2})" -f $Application.name, $StartupScript.Name, $process.Id)
}

try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Configuration file not found: $configPath"
    }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
}
catch {
    Write-Error ("Failed to initialize chan-suite: {0}" -f $_.Exception.Message)
    exit 1
}

foreach ($application in @($config.applications | Where-Object { $_.enabled -eq $true })) {
    try {
        $applicationPath = Join-Path $suiteRoot $application.path
        if (-not (Test-Path -LiteralPath $applicationPath -PathType Container)) {
            Write-Host ("[SKIP] {0}: directory not found" -f $application.name)
            continue
        }

        $runningPorts = @()
        if ($null -ne $application.frontendPort -and (Test-PortListening -Port $application.frontendPort)) {
            Write-Host ("[RUNNING] {0} frontend: port {1}" -f $application.name, $application.frontendPort)
            $runningPorts += $application.frontendPort
        }
        if ($null -ne $application.backendPort -and (Test-PortListening -Port $application.backendPort)) {
            Write-Host ("[RUNNING] {0} backend: port {1}" -f $application.name, $application.backendPort)
            $runningPorts += $application.backendPort
        }
        if ($runningPorts.Count -gt 0) {
            Write-Host ("[SKIP] {0}: at least one configured port is already in use" -f $application.name)
            continue
        }

        $startupScript = Find-StartupScript -ApplicationPath $applicationPath
        if ($null -eq $startupScript) {
            Write-Host ("[WARN] {0}: startup script was not found." -f $application.name)
            continue
        }
        Start-ApplicationScript -Application $application -ApplicationPath $applicationPath -StartupScript $startupScript
    }
    catch {
        Write-Host ("[WARN] {0}: startup failed: {1}" -f $application.name, $_.Exception.Message)
    }
}
