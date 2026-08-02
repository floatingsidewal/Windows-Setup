<#
.SYNOPSIS
  Deploys the bell sound pack to ~/.sounds and points Windows Terminal's
  Defaults | Advanced | Bell sound at it.

.DESCRIPTION
  Terminal's `bellSound` accepts an array and picks one at random per bell, so
  the whole pack becomes the bell.

  The pack ships most sounds as BOTH .mp3 and .wav. Listing both would just
  weight those sounds double in the random pool, so the array is deduplicated by
  base name, preferring -PreferFormat and falling back to whatever else exists
  (e.g. bass_deep-drone is .m4a only).

  Paths written into settings.json are absolute. Terminal does not document
  environment-variable expansion for bellSound, so %USERPROFILE% is not relied on.

.PARAMETER SourcePath
  The repo's .sounds directory.

.PARAMETER Destination
  Where to deploy. Defaults to ~/.sounds.

.PARAMETER PreferFormat
  Which extension wins when a sound exists in several formats.

.EXAMPLE
  .\Install-Sounds.ps1 -SourcePath ..\.sounds -WhatIf
  .\Install-Sounds.ps1 -SourcePath ..\.sounds
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [string]$Destination = (Join-Path $env:USERPROFILE '.sounds'),

    [ValidateSet('wav', 'mp3', 'm4a')]
    [string]$PreferFormat = 'wav'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SourcePath)) { throw "Sound pack not found: $SourcePath" }

$audio = @(Get-ChildItem $SourcePath -File |
    Where-Object { $_.Extension -in '.wav', '.mp3', '.m4a' })

if (-not $audio) { throw "No audio files in $SourcePath" }

# --- deploy -------------------------------------------------------------------
if (-not (Test-Path $Destination)) {
    if ($PSCmdlet.ShouldProcess($Destination, 'Create directory')) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
}

if ($PSCmdlet.ShouldProcess($Destination, "Copy $($audio.Count) sound files")) {
    foreach ($f in $audio) {
        Copy-Item $f.FullName (Join-Path $Destination $f.Name) -Force
    }
    Write-Host "Deployed $($audio.Count) files -> $Destination" -ForegroundColor Green
}

# --- build the bellSound array ------------------------------------------------
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
        Join-Path $Destination $pick.Name
    } | Sort-Object
)

Write-Host "Bell pool: $($bellSound.Count) unique sounds (from $($audio.Count) files)" -ForegroundColor DarkGray

# --- locate Windows Terminal settings.json ------------------------------------
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
        Write-Warning 'Windows Terminal settings.json not found and no LocalState directory. Skipping bell config; sounds are still deployed.'
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

function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

if (-not $settings.profiles)          { Set-JsonProp $settings 'profiles' ([pscustomobject]@{}) }
if (-not $settings.profiles.defaults) { Set-JsonProp $settings.profiles 'defaults' ([pscustomobject]@{}) }

Set-JsonProp $settings.profiles.defaults 'bellSound' $bellSound

# bellStyle defaults to "audible", so we leave it alone - but warn if the current
# value would swallow the sound we just configured.
$style = $settings.profiles.defaults.bellStyle
if ($style -and $style -notin 'all', 'audible') {
    Write-Warning "profiles.defaults.bellStyle is '$style' - the bell will not play audio. Set it to 'audible' or 'all'."
}

if ($PSCmdlet.ShouldProcess($settingsPath, 'Set profiles.defaults.bellSound')) {
    if ($existing) {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        Write-Host "Backed up -> $settingsPath.bak" -ForegroundColor DarkGray
    }
    $settings | ConvertTo-Json -Depth 32 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "Bell sound configured in $settingsPath" -ForegroundColor Green
    if ($existing) {
        Write-Host 'Note: comments in settings.json are not preserved by this rewrite.' -ForegroundColor DarkGray
    }
}
