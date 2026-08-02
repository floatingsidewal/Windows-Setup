<#
.SYNOPSIS
  Provisions a Windows machine from this repo: applies the winget DSC config,
  then enables FancyZones and imports zone layouts.

.DESCRIPTION
  Must run elevated - most resources in config\dev-config.winget declare
  securityContext: elevated, and `winget configure --enable` requires admin.

.PARAMETER FancyZonesSource
  Folder holding custom-layouts.json etc. Defaults to powertoys\fancyzones
  in this repo.

.EXAMPLE
  .\bootstrap.ps1 -WhatIf          # dry run, changes nothing
  .\bootstrap.ps1                  # full provision
  .\bootstrap.ps1 -SkipProvision   # only the FancyZones half
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$FancyZonesSource = (Join-Path $PSScriptRoot 'powertoys\fancyzones'),
    [switch]$SkipProvision,
    [switch]$SkipFancyZones
)

$ErrorActionPreference = 'Stop'

$configFile = Join-Path $PSScriptRoot 'config\dev-config.winget'
$importer   = Join-Path $PSScriptRoot 'powertoys\Import-FancyZones.ps1'

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }

# --- preflight ----------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Must run elevated. Open PowerShell as Administrator and re-run.'
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store first.'
}

# --- provision ----------------------------------------------------------------
if (-not $SkipProvision) {
    if (-not (Test-Path $configFile)) { throw "Config not found: $configFile" }

    Write-Step 'Enabling winget configuration support'
    if ($PSCmdlet.ShouldProcess('winget', 'configure --enable')) {
        winget configure --enable
    }

    Write-Step 'Validating configuration'
    if ($PSCmdlet.ShouldProcess($configFile, 'validate')) {
        winget configure validate -f $configFile
        if ($LASTEXITCODE -ne 0) { throw "Validation failed (exit $LASTEXITCODE)." }
    }

    Write-Step 'Applying configuration (this takes a while)'
    if ($PSCmdlet.ShouldProcess($configFile, 'apply')) {
        winget configure -f $configFile --accept-configuration-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "winget configure exited $LASTEXITCODE - review the output above."
        }
    }
} else {
    Write-Step 'Skipping provision (-SkipProvision)'
}

# --- FancyZones ---------------------------------------------------------------
if ($SkipFancyZones) {
    Write-Step 'Skipping FancyZones (-SkipFancyZones)'
    return
}

Write-Step 'Configuring FancyZones'

$ptRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
if (-not (Test-Path $ptRoot)) {
    Write-Warning @"
PowerToys has not written its settings yet. Launch PowerToys once from the
Start menu, then re-run:  .\bootstrap.ps1 -SkipProvision
"@
    return
}

$layouts = Join-Path $FancyZonesSource 'custom-layouts.json'
if (-not (Test-Path $layouts)) {
    Write-Warning @"
No custom-layouts.json in $FancyZonesSource
Copy these off the other workstation's %LOCALAPPDATA%\Microsoft\PowerToys\FancyZones:
  custom-layouts.json  layout-hotkeys.json  layout-templates.json  default-layouts.json
then re-run:  .\bootstrap.ps1 -SkipProvision
"@
    return
}

$importArgs = @{ SourcePath = $FancyZonesSource }
if ($PSBoundParameters.ContainsKey('WhatIf')) { $importArgs['WhatIf'] = $true }
& $importer @importArgs

Write-Step 'Done'
