function Assert-UniqueApplicationPorts {
    <#
    Validates that enabled applications do not reuse frontend/backend ports.

    Args:
        Applications: Application configuration objects loaded from apps.json.

    Returns:
        None. Throws when a configured port is invalid or duplicated.
    #>
    param([Parameter(Mandatory = $true)]$Applications)

    $ownersByPort = @{}
    foreach ($application in @($Applications | Where-Object { $_.enabled -eq $true })) {
        $endpoints = @(
            [PSCustomObject]@{ Name = 'frontend'; Port = $application.frontendPort }
            [PSCustomObject]@{ Name = 'backend'; Port = $application.backendPort }
        )
        foreach ($endpoint in $endpoints) {
            if ($null -eq $endpoint.Port) {
                continue
            }

            $port = [int]$endpoint.Port
            if ($port -lt 1 -or $port -gt 65535) {
                throw ("Invalid port {0} for {1} {2}." -f $port, $application.name, $endpoint.Name)
            }

            if ($ownersByPort.ContainsKey($port)) {
                throw ("Duplicate port {0}: {1} conflicts with {2} {3}." -f $port, $ownersByPort[$port], $application.name, $endpoint.Name)
            }
            $ownersByPort[$port] = ("{0} {1}" -f $application.name, $endpoint.Name)
        }
    }
}

function Get-ChanSuiteConfiguration {
    <#
    Loads application and execution-profile configuration.

    Args:
        SuiteRoot: Absolute path to the chan-suite repository root.

    Returns:
        Object containing Applications and Profiles configuration.
    #>
    param([Parameter(Mandatory = $true)][string]$SuiteRoot)

    $appsPath = Join-Path $SuiteRoot 'config/apps.json'
    $profilesPath = Join-Path $SuiteRoot 'config/profiles.json'
    if (-not (Test-Path -LiteralPath $appsPath -PathType Leaf)) {
        throw "Configuration file not found: $appsPath"
    }
    if (-not (Test-Path -LiteralPath $profilesPath -PathType Leaf)) {
        throw "Configuration file not found: $profilesPath"
    }

    $applications = (Get-Content -LiteralPath $appsPath -Raw -Encoding UTF8 | ConvertFrom-Json).applications
    $profiles = (Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json).profiles
    Assert-UniqueApplicationPorts -Applications $applications

    return [PSCustomObject]@{
        Applications = $applications
        Profiles = $profiles
    }
}

function Resolve-ChanSuiteProfile {
    <#
    Resolves bind and public hosts for an execution profile.

    Args:
        Profiles: Profile configuration loaded from profiles.json.
        Profile: Local or Intranet.
        ServerHost: Optional explicit public host for Intranet.

    Returns:
        Object containing Profile, BindHost, and PublicHost.
    #>
    param(
        [Parameter(Mandatory = $true)]$Profiles,
        [Parameter(Mandatory = $true)][ValidateSet('Local', 'Intranet')][string]$Profile,
        [AllowEmptyString()][string]$ServerHost
    )

    $profileConfig = $Profiles.($Profile.ToLowerInvariant())
    if ($null -eq $profileConfig) {
        throw "Profile configuration not found: $Profile"
    }

    $publicHost = [string]$profileConfig.publicHost
    if ($Profile -eq 'Intranet') {
        if (-not [string]::IsNullOrWhiteSpace($ServerHost)) {
            $publicHost = $ServerHost.Trim()
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:CHAN_SERVER_HOST)) {
            $publicHost = $env:CHAN_SERVER_HOST.Trim()
        }
        else {
            throw 'Intranet profile requires ServerHost.'
        }
    }

    return [PSCustomObject]@{
        Profile = $Profile
        BindHost = [string]$profileConfig.bindHost
        PublicHost = $publicHost
    }
}

function Get-ChanSuiteUrl {
    <#
    Creates an HTTP URL from a public host and port.

    Args:
        PublicHost: Hostname or IP used by browser clients.
        Port: TCP port exposed by an application.

    Returns:
        HTTP URL string.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PublicHost,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $urlHost = $PublicHost
    if ($PublicHost.Contains(':') -and -not $PublicHost.StartsWith('[')) {
        $urlHost = "[$PublicHost]"
    }
    return ('http://{0}:{1}' -f $urlHost, $Port)
}

function Get-PortListeners {
    <#
    Gets local TCP listeners for a configured port.

    Args:
        Port: TCP port number to inspect.

    Returns:
        Array of active TCP endpoint objects.
    #>
    param([Parameter(Mandatory = $true)][int]$Port)

    return @([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
        Where-Object { $_.Port -eq $Port })
}

function Test-PortListening {
    <#
    Tests whether a local TCP port is listening.

    Args:
        Port: TCP port number to inspect.

    Returns:
        Boolean indicating whether a listener exists.
    #>
    param([Parameter(Mandatory = $true)][int]$Port)

    return (Get-PortListeners -Port $Port).Count -gt 0
}

function Test-PortLoopbackOnly {
    <#
    Tests whether every listener for a port is bound to loopback.

    Args:
        Port: TCP port number to inspect.

    Returns:
        Boolean; false is also returned when there are no listeners.
    #>
    param([Parameter(Mandatory = $true)][int]$Port)

    $listeners = @(Get-PortListeners -Port $Port)
    if ($listeners.Count -eq 0) {
        return $false
    }
    return @($listeners | Where-Object { -not [System.Net.IPAddress]::IsLoopback($_.Address) }).Count -eq 0
}

function Get-ApplicationEnvironment {
    <#
    Creates environment variables inherited by an application launcher.

    Args:
        Application: Application configuration object.
        ResolvedProfile: Resolved execution-profile object.

    Returns:
        Hashtable of standard CHAN variables.
    #>
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)]$ResolvedProfile
    )

    return @{
        CHAN_SUITE_PROFILE = [string]$ResolvedProfile.Profile
        CHAN_BIND_HOST = [string]$ResolvedProfile.BindHost
        CHAN_PUBLIC_HOST = [string]$ResolvedProfile.PublicHost
        CHAN_FRONTEND_PORT = if ($null -eq $Application.frontendPort) { '' } else { [string]$Application.frontendPort }
        CHAN_BACKEND_PORT = if ($null -eq $Application.backendPort) { '' } else { [string]$Application.backendPort }
    }
}

function Get-PortalEnvironment {
    <#
    Creates Vite application-link variables for chan-portal.

    Args:
        Applications: All application configuration objects.
        PublicHost: Hostname or IP used by browser clients.

    Returns:
        Hashtable of VITE_<APP>_URL variables for non-portal frontends.
    #>
    param(
        [Parameter(Mandatory = $true)]$Applications,
        [Parameter(Mandatory = $true)][string]$PublicHost
    )

    $environment = @{}
    foreach ($application in @($Applications)) {
        if ($application.name -eq 'chan-portal' -or $null -eq $application.frontendPort) {
            continue
        }
        $keyName = 'VITE_{0}_URL' -f (($application.name -replace '[^A-Za-z0-9]', '_').ToUpperInvariant())
        $environment[$keyName] = Get-ChanSuiteUrl -PublicHost $PublicHost -Port $application.frontendPort
    }
    return $environment
}
