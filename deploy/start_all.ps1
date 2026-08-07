[CmdletBinding()]
param(
    [ValidateSet('Local', 'Intranet')][string]$Profile = 'Local',
    [string]$ServerHost
)

$ErrorActionPreference = 'Stop'
$suiteRoot = Split-Path -Parent $PSScriptRoot
$logsPath = Join-Path $suiteRoot 'logs'
. (Join-Path $PSScriptRoot 'common.ps1')

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
    Starts one discovered application script with an isolated environment.

    Args:
        Application: Application configuration object.
        ApplicationPath: Absolute path to the application directory.
        StartupScript: Startup script selected by Find-StartupScript.
        Environment: Variables for the child process to inherit.

    Returns:
        None.
    #>
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)][string]$ApplicationPath,
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$StartupScript,
        [Parameter(Mandatory = $true)][hashtable]$Environment
    )

    $stdoutPath = Join-Path $logsPath ($Application.name + '.log')
    $stderrPath = Join-Path $logsPath ($Application.name + '.error.log')
    $savedEnvironment = @{}
    try {
        foreach ($keyName in $Environment.Keys) {
            $savedEnvironment[$keyName] = [Environment]::GetEnvironmentVariable($keyName, 'Process')
            [Environment]::SetEnvironmentVariable($keyName, [string]$Environment[$keyName], 'Process')
        }

        if ($StartupScript.Extension -ieq '.bat') {
            $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', ('call "{0}"' -f $StartupScript.FullName)) `
                -WorkingDirectory $ApplicationPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        }
        else {
            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $StartupScript.FullName)) `
                -WorkingDirectory $ApplicationPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        }
        Write-Host ("[STARTED] {0}: {1} (launcher PID {2})" -f $Application.name, $StartupScript.Name, $process.Id)
    }
    finally {
        foreach ($keyName in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($keyName, $savedEnvironment[$keyName], 'Process')
        }
    }
}

try {
    $configuration = Get-ChanSuiteConfiguration -SuiteRoot $suiteRoot
    $resolvedProfile = Resolve-ChanSuiteProfile -Profiles $configuration.Profiles -Profile $Profile -ServerHost $ServerHost
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
}
catch {
    Write-Host ("[ERROR] {0}" -f $_.Exception.Message)
    exit 1
}

Write-Host ("[PROFILE] {0}; bind host: {1}; public host: {2}" -f $resolvedProfile.Profile, $resolvedProfile.BindHost, $resolvedProfile.PublicHost)

foreach ($application in @($configuration.Applications | Where-Object { $_.enabled -eq $true })) {
    try {
        $applicationPath = Join-Path $suiteRoot $application.path
        if (-not (Test-Path -LiteralPath $applicationPath -PathType Container)) {
            Write-Host ("[SKIP] {0}: directory not found" -f $application.name)
            continue
        }

        $runningPorts = @()
        $endpoints = @(
            [PSCustomObject]@{ Name = 'frontend'; Port = $application.frontendPort }
            [PSCustomObject]@{ Name = 'backend'; Port = $application.backendPort }
        )
        foreach ($endpoint in $endpoints) {
            if ($null -ne $endpoint.Port -and (Test-PortListening -Port $endpoint.Port)) {
                Write-Host ("[RUNNING] {0} {1}: port {2}" -f $application.name, $endpoint.Name, $endpoint.Port)
                if ($Profile -eq 'Intranet' -and (Test-PortLoopbackOnly -Port $endpoint.Port)) {
                    Write-Host ("[WARN] {0} {1} is listening only on loopback." -f $application.name, $endpoint.Name)
                    Write-Host '       It may not be reachable from other PCs.'
                }
                $runningPorts += $endpoint.Port
            }
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

        $applicationEnvironment = Get-ApplicationEnvironment -Application $application -ResolvedProfile $resolvedProfile
        if ($application.name -eq 'chan-portal') {
            $portalEnvironment = Get-PortalEnvironment -Applications $configuration.Applications -PublicHost $resolvedProfile.PublicHost
            foreach ($keyName in $portalEnvironment.Keys) {
                $applicationEnvironment[$keyName] = $portalEnvironment[$keyName]
            }
        }
        Start-ApplicationScript -Application $application -ApplicationPath $applicationPath -StartupScript $startupScript -Environment $applicationEnvironment
    }
    catch {
        Write-Host ("[WARN] {0}: startup failed: {1}" -f $application.name, $_.Exception.Message)
    }
}
