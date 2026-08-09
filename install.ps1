<#
.SYNOPSIS
  One-liner bootstrap. Installs git if needed, clones this repo into ~/git,
  then launches provisioning elevated.

.DESCRIPTION
  Designed to run on a bare Windows 11 box via:

    irm https://raw.githubusercontent.com/floatingsidewal/Windows-Setup/main/install.ps1 | iex

  Must stay Windows PowerShell 5.1 compatible - pwsh 7 is not installed yet at
  the point this runs. No ternaries, no null-coalescing, no -AsHashtable.

  Run this UNELEVATED. It elevates only for the provisioning step, and it
  elevates a real file on disk rather than re-piping remote code into an admin
  shell.

.PARAMETER Branch
  Branch to clone. Defaults to main.

.PARAMETER Workspace
  Where repos live. Defaults to ~/git.

.PARAMETER NoProvision
  Clone only - skip running bootstrap.ps1.

.PARAMETER Mode
  Auto (default), Parallels, or Native. Auto lets bootstrap.ps1 detect the
  machine: a Parallels guest gets the lean profile, anything else additionally
  gets WSL + Ubuntu, Docker Desktop, Hyper-V and Windows Sandbox.

.EXAMPLE
  irm https://raw.githubusercontent.com/floatingsidewal/Windows-Setup/main/install.ps1 | iex

.EXAMPLE
  # `irm | iex` cannot take arguments. To pass them, build a scriptblock:
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/floatingsidewal/Windows-Setup/main/install.ps1))) -NoProvision
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Branch    = 'main',
    [string]$Workspace = (Join-Path $env:USERPROFILE 'git'),
    [switch]$NoProvision,
    # Bindable as -m365; PowerShell parameter matching is case-insensitive.
    [switch]$M365,

    [ValidateSet('Auto', 'Parallels', 'Native')]
    [string]$Mode = 'Auto',

    # Dark mode is opt-in - it is no longer part of the base config.
    [switch]$DarkTheme,

    # Native mode only: install the WSL components but do not reboot.
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'

$RepoName = 'Windows-Setup'
$RepoUrl  = 'https://github.com/floatingsidewal/Windows-Setup.git'
$Target   = Join-Path $Workspace $RepoName

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "    $Text" -ForegroundColor Green }

function Update-SessionPath {
    # Pick up PATH changes made by an installer without restarting the shell.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Get-GitPath {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # winget does not always land git on PATH in the current session.
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

Write-Host ''
Write-Host '  Windows-Setup installer' -ForegroundColor White
Write-Host '  floatingsidewal/Windows-Setup' -ForegroundColor DarkGray

# --- git ----------------------------------------------------------------------
Write-Step 'Checking for git'
$git = Get-GitPath

if (-not $git) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Neither git nor winget found. Install "App Installer" from the Microsoft Store, then re-run.'
    }
    Write-Host '    git not found - installing via winget...' -ForegroundColor Yellow
    winget install --id Git.Git --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    $git = Get-GitPath
    if (-not $git) {
        throw 'git installed but could not be located. Open a new terminal and re-run.'
    }
}
Write-Ok "git: $git"

# --- workspace ----------------------------------------------------------------
Write-Step "Ensuring workspace: $Workspace"
if (Test-Path $Workspace -PathType Leaf) {
    throw "A file exists at $Workspace - move it before continuing."
}
if (-not (Test-Path $Workspace -PathType Container)) {
    New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
    Write-Ok 'created'
} else {
    Write-Ok 'already present'
}

# --- clone or update ----------------------------------------------------------
if (Test-Path (Join-Path $Target '.git')) {
    Write-Step "Repo already at $Target - updating"
    & $git -C $Target fetch origin $Branch
    # --ff-only so local edits are never silently discarded.
    & $git -C $Target pull --ff-only origin $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Fast-forward failed - you have local commits or changes. Resolve manually; continuing with what is on disk.'
    } else {
        Write-Ok 'up to date'
    }
} elseif (Test-Path $Target) {
    throw "$Target exists but is not a git repo. Move or delete it, then re-run."
} else {
    Write-Step "Cloning into $Target"
    & $git clone --branch $Branch $RepoUrl $Target
    if ($LASTEXITCODE -ne 0) { throw "Clone failed (exit $LASTEXITCODE)." }
    Write-Ok 'cloned'
}

# --- provision ----------------------------------------------------------------
if ($NoProvision) {
    Write-Step 'Skipping provisioning (-NoProvision)'
    Write-Host "`nRepo is at $Target" -ForegroundColor Cyan
    return
}

$bootstrap = Join-Path $Target 'bootstrap.ps1'
if (-not (Test-Path $bootstrap)) { throw "bootstrap.ps1 not found at $bootstrap" }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)

if (Get-Command pwsh -ErrorAction SilentlyContinue) { $shell = 'pwsh' }
else { $shell = 'powershell' }

# RepoRoot is passed explicitly to every branch below. Windows `sudo` inline mode
# runs the script with $PSScriptRoot empty even though -File resolved fine, so
# bootstrap.ps1 cannot infer its own location reliably.

if ($M365)     { Write-Host '    M365 requested - OneDrive + Microsoft 365 Apps will be installed' -ForegroundColor DarkGray }
if ($DarkTheme){ Write-Host '    Dark theme requested' -ForegroundColor DarkGray }
if ($NoReboot) { Write-Host '    -NoReboot: WSL components install but the machine will not restart' -ForegroundColor DarkGray }

# Built once and reused by all three launch paths below. Adding a switch here
# used to mean adding an if/else to each branch, which does not scale.
$passthru = @()
if ($Mode -ne 'Auto') { $passthru += @('-Mode', $Mode) }
if ($M365)            { $passthru += '-M365' }
if ($DarkTheme)       { $passthru += '-DarkTheme' }
if ($NoReboot)        { $passthru += '-NoReboot' }

# bootstrap.ps1 reports the detected mode itself, but say something here too so
# the unelevated window shows it even when provisioning detaches into its own.
if ($Mode -eq 'Auto') {
    $profileLib = Join-Path $Target 'lib\Get-MachineProfile.ps1'
    if (Test-Path $profileLib) {
        . $profileLib
        $detected = Get-MachineProfile
        Write-Host "    detected mode: $($detected.Mode) ($($detected.Platform))" -ForegroundColor DarkGray
    }
} else {
    Write-Host "    mode: $Mode (forced)" -ForegroundColor DarkGray
}

if ($isAdmin) {
    Write-Step 'Already elevated - running bootstrap.ps1 here'
    & $bootstrap -RepoRoot $Target @passthru
    return
}

# Prefer Windows `sudo` in inline mode: elevation happens without detaching, so
# provisioning output stays in this window. Falls back to a separate elevated
# window if sudo is absent (pre-24H2) or disabled.
$sudo = Get-Command sudo.exe -ErrorAction SilentlyContinue

if ($sudo) {
    Write-Step 'Elevating via sudo (a UAC prompt is expected)'
    & $sudo.Source $shell -ExecutionPolicy Bypass -File $bootstrap -RepoRoot $Target @passthru
    if ($LASTEXITCODE -eq 0) { return }
    Write-Warning "sudo returned $LASTEXITCODE - falling back to a separate elevated window."
}

Write-Step 'Launching bootstrap.ps1 in an elevated window'
Write-Host '    (a UAC prompt is expected)' -ForegroundColor DarkGray
$bootstrapArgs = @(
    '-NoExit'
    '-ExecutionPolicy', 'Bypass'
    '-File', "`"$bootstrap`""
    '-RepoRoot', "`"$Target`""
)
$bootstrapArgs += $passthru
Start-Process -FilePath $shell -Verb RunAs -ArgumentList $bootstrapArgs
Write-Ok 'elevated window launched - watch it for progress'
