<#
.SYNOPSIS
  Configures Windows Terminal: deploys the bell sound pack to ~/.sounds, points
  Defaults | Advanced | Bell sound at it, and turns off the paste warnings.

.DESCRIPTION
  Every setting here lives in the same settings.json, so they are applied in a
  single read-modify-write with one backup.

  Terminal's `bellSound` accepts an array and picks one at random per bell, so
  the whole pack becomes the bell.

  The pack ships most sounds as BOTH .mp3 and .wav. Listing both would weight
  those sounds double in the random pool, so the array is deduplicated by base
  name, preferring -PreferFormat and falling back to whatever else exists
  (e.g. bass_deep-drone is .m4a only).

  Paths written into settings.json are absolute. Terminal does not document
  environment-variable expansion for bellSound, so %USERPROFILE% is not relied on.

.PARAMETER SoundsSource
  The repo's .sounds directory.

.PARAMETER SoundsDestination
  Where to deploy. Defaults to ~/.sounds.

.PARAMETER PreferFormat
  Which extension wins when a sound exists in several formats.

.PARAMETER LargePasteWarning
  Terminal's >5 KiB paste confirmation. Default $false (no prompt).

.PARAMETER MultiLinePasteWarning
  Terminal's multi-line paste confirmation. Default $false (no prompt).
  NOTE: this dialog is a guard against pasting multi-line text that a shell will
  execute immediately. Pass $true to keep it.

.EXAMPLE
  .\Configure-Terminal.ps1 -SoundsSource ..\.sounds -WhatIf
  .\Configure-Terminal.ps1 -SoundsSource ..\.sounds
  .\Configure-Terminal.ps1 -SoundsSource ..\.sounds -MultiLinePasteWarning $true
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SoundsSource,

    [string]$SoundsDestination = (Join-Path $env:USERPROFILE '.sounds'),

    [ValidateSet('wav', 'mp3', 'm4a')]
    [string]$PreferFormat = 'wav',

    [bool]$LargePasteWarning    = $false,
    [bool]$MultiLinePasteWarning = $false,

    [switch]$SkipSounds
)

$ErrorActionPreference = 'Stop'

function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- sounds: deploy and build the bell pool -----------------------------------
$bellSound = $null

if (-not $SkipSounds) {
    if (-not (Test-Path $SoundsSource)) { throw "Sound pack not found: $SoundsSource" }

    $audio = @(Get-ChildItem $SoundsSource -File |
        Where-Object { $_.Extension -in '.wav', '.mp3', '.m4a' })

    if (-not $audio) { throw "No audio files in $SoundsSource" }

    if (-not (Test-Path $SoundsDestination)) {
        if ($PSCmdlet.ShouldProcess($SoundsDestination, 'Create directory')) {
            New-Item -ItemType Directory -Path $SoundsDestination -Force | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($SoundsDestination, "Copy $($audio.Count) sound files")) {
        foreach ($f in $audio) {
            Copy-Item $f.FullName (Join-Path $SoundsDestination $f.Name) -Force
        }
        Write-Host "Deployed $($audio.Count) files -> $SoundsDestination" -ForegroundColor Green
    }

    # One entry per unique sound, preferring $PreferFormat.
    $order = @($PreferFormat, 'wav', 'mp3', 'm4a') | Select-Object -Unique
    $bellSound = @(
        $audio | Group-Object BaseName | ForEach-Object {
            $pick = $null
            foreach ($ext in $order) {
                $pick = $_.Group | Where-Object { $_.Extension -eq ".$ext" } | Select-Object -First 1
                if ($pick) { break }
            }
            if (-not $pick) { $pick = $_.Group | Select-Object -First 1 }
            Join-Path $SoundsDestination $pick.Name
        } | Sort-Object
    )

    Write-Host "Bell pool: $($bellSound.Count) unique sounds (from $($audio.Count) files)" -ForegroundColor DarkGray
}

# --- locate settings.json -----------------------------------------------------
$candidates = @(
    Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'Microsoft.WindowsTerminal*' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'LocalState\settings.json' }
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
$settingsPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $settingsPath) {
    # Terminal installed but never launched: LocalState exists, settings.json does not.
    $localState = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'Microsoft.WindowsTerminal*' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'LocalState' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($localState) {
        $settingsPath = Join-Path $localState 'settings.json'
        Write-Host 'Terminal has not been launched yet - seeding settings.json.' -ForegroundColor DarkGray
    } else {
        Write-Warning 'Windows Terminal settings.json not found and no LocalState directory. Skipping Terminal config; sounds are still deployed.'
        return
    }
}

# --- read (settings.json is JSONC - strip comments before parsing) ------------
if (Test-Path $settingsPath) {
    $raw   = Get-Content $settingsPath -Raw
    $clean = [regex]::Replace($raw, '/\*[\s\S]*?\*/', '')
    $clean = [regex]::Replace($clean, '(?m)^\s*//.*$', '')
    $settings = $clean | ConvertFrom-Json
    $existing = $true
} else {
    $settings = [pscustomobject]@{}
    $existing = $false
}

# --- bell sound (per-profile defaults) ----------------------------------------
if ($bellSound) {
    if (-not $settings.profiles)          { Set-JsonProp $settings 'profiles' ([pscustomobject]@{}) }
    if (-not $settings.profiles.defaults) { Set-JsonProp $settings.profiles 'defaults' ([pscustomobject]@{}) }

    Set-JsonProp $settings.profiles.defaults 'bellSound' $bellSound

    # bellStyle defaults to "audible", so we leave it alone - but warn if the
    # current value would swallow the sound we just configured.
    $style = $settings.profiles.defaults.bellStyle
    if ($style -and $style -notin 'all', 'audible') {
        Write-Warning "profiles.defaults.bellStyle is '$style' - the bell will not play audio. Set it to 'audible' or 'all'."
    }
}

# --- paste warnings (root-level globals, NOT per-profile) ---------------------
Set-JsonProp $settings 'largePasteWarning'    $LargePasteWarning
Set-JsonProp $settings 'multiLinePasteWarning' $MultiLinePasteWarning

Write-Host "largePasteWarning = $LargePasteWarning, multiLinePasteWarning = $MultiLinePasteWarning" -ForegroundColor DarkGray

# --- write once ---------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($settingsPath, 'Update Windows Terminal settings')) {
    if ($existing) {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        Write-Host "Backed up -> $settingsPath.bak" -ForegroundColor DarkGray
    }
    $settings | ConvertTo-Json -Depth 32 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "Windows Terminal configured: $settingsPath" -ForegroundColor Green
    if ($existing) {
        Write-Host 'Note: comments in settings.json are not preserved by this rewrite.' -ForegroundColor DarkGray
    }
}
