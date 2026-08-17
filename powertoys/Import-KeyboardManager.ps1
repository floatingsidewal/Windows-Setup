<#
.SYNOPSIS
  Enables PowerToys Keyboard Manager and imports the macOS-compatible remaps
  tracked in this repo.

.PARAMETER SourcePath
  Folder holding default.json / editorSettings.json - i.e. a copy of
  %LOCALAPPDATA%\Microsoft\PowerToys\Keyboard Manager.

.EXAMPLE
  .\Import-KeyboardManager.ps1 -SourcePath .\keyboard-manager -WhatIf
  .\Import-KeyboardManager.ps1 -SourcePath .\keyboard-manager
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'

$ptRoot   = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$kbmDir   = Join-Path $ptRoot 'Keyboard Manager'
$rootJson = Join-Path $ptRoot 'settings.json'
$kbmJson  = Join-Path $kbmDir 'settings.json'

if (-not (Test-Path $SourcePath)) { throw "SourcePath not found: $SourcePath" }

# Locate the installed binary. This - not the settings directory - is what tells
# us PowerToys is actually present.
$exe = @(
    (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe')
    (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe')
    (Join-Path ${env:ProgramFiles(x86)} 'PowerToys\PowerToys.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $exe) {
    throw 'PowerToys is not installed. Run bootstrap.ps1 (or: winget install --id Microsoft.PowerToys) first.'
}

# PowerToys only creates %LOCALAPPDATA%\Microsoft\PowerToys on its FIRST RUN.
# Seed it rather than making the user launch PowerToys by hand; it merges in
# defaults for anything absent, so a partial tree is fine.
if (-not (Test-Path $ptRoot)) {
    if ($PSCmdlet.ShouldProcess($ptRoot, 'Create PowerToys settings directory (first run not yet performed)')) {
        New-Item -ItemType Directory -Path $ptRoot -Force | Out-Null
        Write-Host 'PowerToys has not run yet - seeding its settings directory.' -ForegroundColor DarkGray
    }
}

# default.json      - what the remap engine actually reads.
# editorSettings.json - what the WinUI3 editor UI reads. Ship both: with only
#                       default.json the remaps work but the editor renders an
#                       empty list and wipes them on the next save.
$files = @('default.json', 'editorSettings.json')

# --- stop PowerToys so it does not overwrite what we write -------------------
$wasRunning = @(Get-Process -Name 'PowerToys' -ErrorAction SilentlyContinue)
if ($wasRunning) {
    if ($PSCmdlet.ShouldProcess('PowerToys.exe', 'Stop process')) {
        $wasRunning | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Host 'Stopped PowerToys.' -ForegroundColor DarkGray
    }
}

# --- back up current Keyboard Manager state -----------------------------------
if (Test-Path $kbmDir) {
    $stamp  = (Get-Item $kbmDir).LastWriteTime.ToString('yyyyMMdd-HHmmss')
    $backup = "$kbmDir.bak-$stamp"
    if ($PSCmdlet.ShouldProcess($backup, 'Create backup')) {
        Copy-Item $kbmDir $backup -Recurse -Force
        Write-Host "Backed up existing Keyboard Manager config -> $backup" -ForegroundColor DarkGray
    }
} else {
    if ($PSCmdlet.ShouldProcess($kbmDir, 'Create directory')) {
        New-Item -ItemType Directory -Path $kbmDir -Force | Out-Null
    }
}

# --- copy the remap files -----------------------------------------------------
foreach ($file in $files) {
    $src = Join-Path $SourcePath $file
    if (-not (Test-Path $src)) {
        Write-Host "  skip (not in source): $file" -ForegroundColor DarkGray
        continue
    }
    # Fail early on malformed json rather than half-importing.
    try { Get-Content $src -Raw | ConvertFrom-Json | Out-Null }
    catch { throw "Source file is not valid JSON: $src" }

    if ($PSCmdlet.ShouldProcess((Join-Path $kbmDir $file), 'Copy remap file')) {
        Copy-Item $src (Join-Path $kbmDir $file) -Force
        Write-Host "  imported: $file" -ForegroundColor Green
    }
}

# --- helper: set a value inside a PSCustomObject, creating it if absent -------
function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- enable the Keyboard Manager module --------------------------------------
# Absent settings.json means PowerToys has never run. Write a minimal one rather
# than bailing; PowerToys merges in defaults for every key we omit.
if (Test-Path $rootJson) {
    $root = Get-Content $rootJson -Raw | ConvertFrom-Json
    $backup = $true
} else {
    $root = [pscustomobject]@{}
    $backup = $false
}

if (-not $root.enabled) { Set-JsonProp $root 'enabled' ([pscustomobject]@{}) }
# Note the space: unlike FancyZones, this module's key is 'Keyboard Manager'.
Set-JsonProp $root.enabled 'Keyboard Manager' $true

if ($PSCmdlet.ShouldProcess($rootJson, 'Enable Keyboard Manager module')) {
    if ($backup) { Copy-Item $rootJson "$rootJson.bak" -Force }
    $root | ConvertTo-Json -Depth 32 | Set-Content $rootJson -Encoding UTF8
    Write-Host 'Enabled Keyboard Manager module.' -ForegroundColor Green
}

# --- point the module at the profile we just imported -------------------------
# Only these two properties are touched. The rest of this file (notably
# EditorShortcut, which is a bare object rather than a { value } wrapper) is
# left exactly as PowerToys wrote it.
if (-not (Test-Path $kbmJson)) {
    $kbm = [pscustomobject]@{
        name       = 'Keyboard Manager'
        version    = '1'
        properties = [pscustomobject]@{}
    }
} else {
    $kbm = Get-Content $kbmJson -Raw | ConvertFrom-Json
    if (-not $kbm.properties) { Set-JsonProp $kbm 'properties' ([pscustomobject]@{}) }
}

Set-JsonProp $kbm.properties 'activeConfiguration'    ([pscustomobject]@{ value = 'default' })
Set-JsonProp $kbm.properties 'keyboardConfigurations' ([pscustomobject]@{ value = @('default') })

if ($PSCmdlet.ShouldProcess($kbmJson, 'Select the "default" remap profile')) {
    $kbm | ConvertTo-Json -Depth 32 | Set-Content $kbmJson -Encoding UTF8
    Write-Host 'Selected the "default" remap profile.' -ForegroundColor Green
}

# --- start PowerToys ----------------------------------------------------------
if ($PSCmdlet.ShouldProcess($exe, 'Start PowerToys')) {
    Start-Process $exe
    if ($wasRunning) { Write-Host 'Restarted PowerToys.' -ForegroundColor Green }
    else             { Write-Host 'Started PowerToys.'   -ForegroundColor Green }
}
