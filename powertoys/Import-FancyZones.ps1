<#
.SYNOPSIS
  Enables FancyZones, imports custom layouts from another workstation, and makes
  FancyZones take over the Win+Arrow snap hotkeys.

.PARAMETER SourcePath
  Folder holding the FancyZones json files copied off the other machine
  (i.e. a copy of that machine's %LOCALAPPDATA%\Microsoft\PowerToys\FancyZones).

.PARAMETER IncludeMonitorAssignments
  Also copy applied-layouts.json / app-zone-history.json. These key off monitor
  hardware IDs, so they normally do NOT match on a different machine (especially
  a Parallels virtual display). Off by default.

.EXAMPLE
  .\Import-FancyZones.ps1 -SourcePath 'D:\backup\FancyZones' -WhatIf
  .\Import-FancyZones.ps1 -SourcePath 'D:\backup\FancyZones'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [switch]$IncludeMonitorAssignments
)

$ErrorActionPreference = 'Stop'

$ptRoot   = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$fzDir    = Join-Path $ptRoot 'FancyZones'
$rootJson = Join-Path $ptRoot 'settings.json'
$fzJson   = Join-Path $fzDir  'settings.json'

if (-not (Test-Path $ptRoot))     { throw "PowerToys not found at $ptRoot. Install it and launch it once first." }
if (-not (Test-Path $SourcePath)) { throw "SourcePath not found: $SourcePath" }

# Layout data that is portable between machines.
$portable = @(
    'custom-layouts.json'      # the zone layouts themselves
    'layout-hotkeys.json'      # Win+Ctrl+Alt+<n> quick-switch bindings
    'layout-templates.json'    # tweaks to the built-in templates
    'default-layouts.json'     # default layout per monitor orientation
)
# Machine-specific: keyed by monitor device id / resolution.
$machineSpecific = @('applied-layouts.json', 'app-zone-history.json')

$toCopy = $portable
if ($IncludeMonitorAssignments) { $toCopy += $machineSpecific }

# --- stop PowerToys so it does not overwrite what we write -------------------
$wasRunning = @(Get-Process -Name 'PowerToys' -ErrorAction SilentlyContinue)
if ($wasRunning) {
    if ($PSCmdlet.ShouldProcess('PowerToys.exe', 'Stop process')) {
        $wasRunning | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Host 'Stopped PowerToys.' -ForegroundColor DarkGray
    }
}

# --- back up current FancyZones state ----------------------------------------
if (Test-Path $fzDir) {
    $stamp  = (Get-Item $fzDir).LastWriteTime.ToString('yyyyMMdd-HHmmss')
    $backup = "$fzDir.bak-$stamp"
    if ($PSCmdlet.ShouldProcess($backup, 'Create backup')) {
        Copy-Item $fzDir $backup -Recurse -Force
        Write-Host "Backed up existing FancyZones config -> $backup" -ForegroundColor DarkGray
    }
} else {
    if ($PSCmdlet.ShouldProcess($fzDir, 'Create directory')) {
        New-Item -ItemType Directory -Path $fzDir -Force | Out-Null
    }
}

# --- copy the layout files ----------------------------------------------------
foreach ($file in $toCopy) {
    $src = Join-Path $SourcePath $file
    if (-not (Test-Path $src)) {
        Write-Host "  skip (not in source): $file" -ForegroundColor DarkGray
        continue
    }
    # Fail early on malformed json rather than half-importing.
    try { Get-Content $src -Raw | ConvertFrom-Json | Out-Null }
    catch { throw "Source file is not valid JSON: $src" }

    if ($PSCmdlet.ShouldProcess((Join-Path $fzDir $file), 'Copy layout file')) {
        Copy-Item $src (Join-Path $fzDir $file) -Force
        Write-Host "  imported: $file" -ForegroundColor Green
    }
}

if (-not $IncludeMonitorAssignments) {
    Write-Host 'Monitor->layout assignments were NOT imported (they are hardware-keyed).' -ForegroundColor Yellow
    Write-Host 'Assign layouts to this display in the editor: Win+Shift+`' -ForegroundColor Yellow
}

# --- helper: set a value inside a PSCustomObject, creating it if absent -------
function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- enable the FancyZones module --------------------------------------------
if (Test-Path $rootJson) {
    $root = Get-Content $rootJson -Raw | ConvertFrom-Json
    if (-not $root.enabled) { Set-JsonProp $root 'enabled' ([pscustomobject]@{}) }
    Set-JsonProp $root.enabled 'FancyZones' $true
    if ($PSCmdlet.ShouldProcess($rootJson, 'Enable FancyZones module')) {
        Copy-Item $rootJson "$rootJson.bak" -Force
        $root | ConvertTo-Json -Depth 32 | Set-Content $rootJson -Encoding UTF8
        Write-Host 'Enabled FancyZones module.' -ForegroundColor Green
    }
} else {
    Write-Warning "$rootJson not found - launch PowerToys once, then re-run."
}

# --- override Windows Snap ----------------------------------------------------
# fancyzones_overrideSnapHotkeys      -> Win+Arrow moves between zones
# fancyzones_moveWindowsBasedOnPosition -> "Relative position" (overrides all four
#                                          arrows + enables Win+Ctrl+Alt+Arrow to
#                                          span multiple zones). Without it only
#                                          Win+Left / Win+Right are overridden.
# fancyzones_moveWindowAcrossMonitors -> cycle through zones on all monitors
$desired = @{
    fancyzones_overrideSnapHotkeys       = $true
    fancyzones_moveWindowsBasedOnPosition = $true
    fancyzones_moveWindowAcrossMonitors   = $true
}

if (-not (Test-Path $fzJson)) {
    $fz = [pscustomobject]@{
        name       = 'FancyZones'
        version    = '1.0'
        properties = [pscustomobject]@{}
    }
} else {
    $fz = Get-Content $fzJson -Raw | ConvertFrom-Json
    if (-not $fz.properties) { Set-JsonProp $fz 'properties' ([pscustomobject]@{}) }
}

foreach ($key in $desired.Keys) {
    Set-JsonProp $fz.properties $key ([pscustomobject]@{ value = $desired[$key] })
}

if ($PSCmdlet.ShouldProcess($fzJson, 'Write FancyZones snap-override settings')) {
    $fz | ConvertTo-Json -Depth 32 | Set-Content $fzJson -Encoding UTF8
    Write-Host 'Set: override Windows Snap = on, move windows based on = relative position.' -ForegroundColor Green
}

# --- restart PowerToys --------------------------------------------------------
$exe = Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe'
if (-not (Test-Path $exe)) { $exe = 'C:\Program Files\PowerToys\PowerToys.exe' }

if (Test-Path $exe) {
    if ($PSCmdlet.ShouldProcess($exe, 'Start PowerToys')) {
        Start-Process $exe
        Write-Host 'Restarted PowerToys.' -ForegroundColor Green
    }
} else {
    Write-Warning "PowerToys.exe not found - start it from the Start menu."
}

Write-Host ''
Write-Host 'Next: press Win+Shift+` to open the layout editor and assign an imported' -ForegroundColor Cyan
Write-Host 'layout to this display, then test with Win+Left / Win+Right.' -ForegroundColor Cyan
