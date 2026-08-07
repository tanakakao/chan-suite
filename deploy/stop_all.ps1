[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$suiteRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $suiteRoot 'config/apps.json'

try {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Write-Error ("Failed to read configuration '{0}': {1}" -f $configPath, $_.Exception.Message)
    exit 1
}

Write-Host 'CHAN SUITE STOP'
Write-Host ''
Write-Warning 'Safe managed-process shutdown is not implemented in this initial version.'
Write-Host 'No process was stopped. Stop each application with its own shutdown procedure or terminal.'
Write-Host 'Port-based termination is intentionally not used because it could stop unrelated processes.'

foreach ($application in @($config.applications | Where-Object { $_.enabled -eq $true })) {
    Write-Host ("[MANUAL] {0}: use the application's own shutdown procedure" -f $application.name)
}
