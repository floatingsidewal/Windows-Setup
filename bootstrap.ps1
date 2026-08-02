<#
.SYNOPSIS
  Provisions a Windows machine from this repo: applies the winget DSC config,
  then enables FancyZones and imports zone layouts.

.DESCRIPTION
  Must run elevated - most resources in config\dev-config.winget declare
  securityContext: elevated, and `winget configure --enable` requires admin.

.PARAMETER RepoRoot
  Root of this repo. Normally inferred, but pass it explicitly when the caller
  cannot guarantee $PSScriptRoot is populated - Windows `sudo` inline mode runs
  the script with $PSScriptRoot empty even though -File resolved correctly.

.PARAMETER FancyZonesSource
  Folder holding custom-layouts.json etc. Defaults to powertoys\fancyzones
  under RepoRoot.

.EXAMPLE
  .\bootstrap.ps1 -WhatIf          # dry run, changes nothing
  .\bootstrap.ps1                  # full provision
  .\bootstrap.ps1 -SkipProvision   # only the FancyZones half
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot,
    [string]$FancyZonesSource,
    [switch]$SkipProvision,
    [switch]$SkipFancyZones,
    # Bindable as -m365; PowerShell parameter matching is case-insensitive.
    [switch]$M365,
    # Internal: set on the sudo-elevated re-invoke to prevent an elevation loop.
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

# --- locate the repo ----------------------------------------------------------
# $PSScriptRoot is NOT reliable here. Under `sudo` inline mode it comes back
# empty, which silently poisoned Join-Path in the param block. Resolve through a
# fallback chain and verify the result actually looks like this repo.
if (-not $RepoRoot) {
    $candidates = @(
        $PSScriptRoot
        if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
        (Get-Location).Path
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'config\dev-config.winget'))) {
            $RepoRoot = $c
            break
        }
    }
}

if (-not $RepoRoot -or -not (Test-Path (Join-Path $RepoRoot 'config\dev-config.winget'))) {
    throw @"
Could not locate the repo root. Re-run from the repo directory, or pass it:
  .\bootstrap.ps1 -RepoRoot C:\Users\<you>\git\Windows-Setup
"@
}

if (-not $FancyZonesSource) {
    $FancyZonesSource = Join-Path $RepoRoot 'powertoys\fancyzones'
}

$configFile = Join-Path $RepoRoot 'config\dev-config.winget'
$m365File   = Join-Path $RepoRoot 'config\m365.winget'
$importer   = Join-Path $RepoRoot 'powertoys\Import-FancyZones.ps1'

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }

# --- preflight ----------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # -NoElevate guards against a loop if the elevated child still reads as
    # non-admin for any reason.
    $sudo = Get-Command sudo.exe -ErrorAction SilentlyContinue

    if ($NoElevate -or -not $sudo) {
        throw @"
Must run elevated. Either:
  sudo .\bootstrap.ps1
or open PowerShell as Administrator and re-run.
"@
    }

    Write-Step 'Not elevated - re-invoking via sudo (a UAC prompt is expected)'

    if (Get-Command pwsh -ErrorAction SilentlyContinue) { $shell = 'pwsh' }
    else { $shell = 'powershell' }

    # Forward every parameter explicitly. $PSCommandPath is not trusted here for
    # the same reason $PSScriptRoot isn't - see the RepoRoot note above.
    $fwd = @(
        '-ExecutionPolicy', 'Bypass'
        '-File', (Join-Path $RepoRoot 'bootstrap.ps1')
        '-RepoRoot', $RepoRoot
        '-FancyZonesSource', $FancyZonesSource
        '-NoElevate'
    )
    if ($SkipProvision)  { $fwd += '-SkipProvision' }
    if ($SkipFancyZones) { $fwd += '-SkipFancyZones' }
    if ($M365)           { $fwd += '-M365' }
    if ($WhatIfPreference) { $fwd += '-WhatIf' }

    & $sudo.Source $shell @fwd
    exit $LASTEXITCODE
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store first.'
}

# --- provision ----------------------------------------------------------------
if (-not $SkipProvision) {
    if (-not (Test-Path $configFile)) { throw "Config not found: $configFile" }

    # `winget configure --enable` first pulls any pending App Installer update
    # from the Microsoft Store and does not complete until that lands - which
    # looks exactly like a silent hang. Get the update out of the way first.
    # A non-zero exit here just means "already current", so it is not checked.
    Write-Step 'Ensuring App Installer is current'
    if ($PSCmdlet.ShouldProcess('Microsoft.AppInstaller', 'upgrade')) {
        winget upgrade --id Microsoft.AppInstaller `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
    }

    Write-Step 'Enabling winget configuration support'
    if ($PSCmdlet.ShouldProcess('winget', 'configure --enable')) {
        winget configure --enable
        if ($LASTEXITCODE -ne 0) {
            throw @"
'winget configure --enable' failed (exit $LASTEXITCODE).

This is an administrator setting and needs an elevated shell. If it was elevated,
App Installer likely has a pending Store update - it must finish before
configuration can be enabled. Try:

  winget upgrade --id Microsoft.AppInstaller
  (open a NEW elevated terminal so the update takes effect)
  winget configure --enable
"@
        }
    }

    # ADVISORY ONLY - do not gate on this.
    # `winget configure validate` exits 1 for purely informational notes such as
    # "The module was not provided" and "not available publicly", which every
    # unit in this config produces (upstream's included). Treating non-zero as
    # fatal aborts every run. The real gate is the apply below.
    Write-Step 'Validating configuration (advisory)'
    if ($PSCmdlet.ShouldProcess($configFile, 'validate')) {
        winget configure validate -f $configFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    validate exited $LASTEXITCODE - typically warnings only, continuing." -ForegroundColor DarkGray
        }
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

# --- M365 (opt-in) ------------------------------------------------------------
# Kept in a separate config so the base provision stays lean. Microsoft 365 Apps
# is a large Click-to-Run download and will dominate this step's runtime.
if ($M365) {
    if (-not (Test-Path $m365File)) { throw "M365 config not found: $m365File" }

    Write-Step 'Validating M365 configuration (advisory)'
    if ($PSCmdlet.ShouldProcess($m365File, 'validate')) {
        winget configure validate -f $m365File
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    validate exited $LASTEXITCODE - typically warnings only, continuing." -ForegroundColor DarkGray
        }
    }

    Write-Step 'Installing OneDrive and Microsoft 365 Apps (large download)'
    if ($PSCmdlet.ShouldProcess($m365File, 'apply')) {
        winget configure -f $m365File --accept-configuration-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "M365 configure exited $LASTEXITCODE - review the output above."
        }
    }
} else {
    Write-Step 'Skipping M365 (pass -m365 to install OneDrive + Microsoft 365 Apps)'
}

# --- Windows Terminal -----------------------------------------------------------
# Ahead of FancyZones, because -SkipFancyZones returns early.
Write-Step 'Configuring Windows Terminal (bell sounds, paste warnings)'
$soundsSource   = Join-Path $RepoRoot '.sounds'
$terminalScript = Join-Path $RepoRoot 'dotfiles\Configure-Terminal.ps1'

if (-not (Test-Path $terminalScript)) {
    Write-Warning "Configure-Terminal.ps1 not found at $terminalScript - skipping."
} else {
    $termArgs = @{ SoundsSource = $soundsSource }
    if (-not (Test-Path $soundsSource)) {
        Write-Warning "No .sounds directory at $soundsSource - configuring Terminal without the bell pack."
        $termArgs['SkipSounds'] = $true
    }
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $termArgs['WhatIf'] = $true }
    & $terminalScript @termArgs
}

# --- FancyZones ---------------------------------------------------------------
if ($SkipFancyZones) {
    Write-Step 'Skipping FancyZones (-SkipFancyZones)'
    return
}

Write-Step 'Configuring FancyZones'

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
