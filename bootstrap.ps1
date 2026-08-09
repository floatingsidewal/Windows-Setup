<#
.SYNOPSIS
  Provisions a Windows machine from this repo: applies the winget DSC config,
  then enables FancyZones and imports zone layouts.

.DESCRIPTION
  Must run elevated - most resources in config\dev-config.winget declare
  securityContext: elevated, and `winget configure --enable` requires admin.

  Two modes, chosen automatically:

    Parallels - the lean profile this repo started as. A Parallels guest has no
                nested virtualization, so WSL, Docker and Hyper-V are skipped.

    Native    - anything that is not a Parallels guest. Layers
                config\native.winget and config\native-post.winget on top of the
                base config: WSL + Ubuntu, Docker Desktop, Hyper-V, Containers
                and Windows Sandbox.

  Detection lives in lib\Get-MachineProfile.ps1. Use -DetectOnly to see what
  this machine reads as without changing anything.

.PARAMETER RepoRoot
  Root of this repo. Normally inferred, but pass it explicitly when the caller
  cannot guarantee $PSScriptRoot is populated - Windows `sudo` inline mode runs
  the script with $PSScriptRoot empty even though -File resolved correctly.

.PARAMETER Mode
  Auto (default), Parallels, or Native. Auto detects the machine.

.PARAMETER FancyZonesSource
  Folder holding custom-layouts.json etc. Defaults to powertoys\fancyzones
  under RepoRoot.

.PARAMETER DarkTheme
  Opt in to forcing dark mode (config\theme.winget). Off by default.

.PARAMETER NoReboot
  Native mode only. Install the WSL components but never reboot; the Ubuntu
  distro and Docker Desktop are left for a later run.

.EXAMPLE
  .\bootstrap.ps1 -DetectOnly      # report the detected mode, change nothing
  .\bootstrap.ps1 -WhatIf          # dry run, changes nothing
  .\bootstrap.ps1                  # full provision, mode auto-detected
  .\bootstrap.ps1 -Mode Parallels  # force the lean profile on any machine
  .\bootstrap.ps1 -SkipProvision   # only the FancyZones half
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot,
    [string]$FancyZonesSource,

    [ValidateSet('Auto', 'Parallels', 'Native')]
    [string]$Mode = 'Auto',

    [switch]$SkipProvision,
    [switch]$SkipFancyZones,
    # Bindable as -m365; PowerShell parameter matching is case-insensitive.
    [switch]$M365,
    # Dark mode is opt-in. It used to be unconditional in dev-config.winget.
    [switch]$DarkTheme,
    # Native mode: enable WSL but leave the machine up, skipping the post-reboot half.
    [switch]$NoReboot,
    # Print the detected machine profile and exit.
    [switch]$DetectOnly,
    # Internal: set by the post-reboot RunOnce resume. Skips straight to the
    # native post-reboot config.
    [switch]$Resume,
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
  .\bootstrap.ps1 -RepoRoot <path-to>\Windows-Setup
"@
}

if (-not $FancyZonesSource) {
    $FancyZonesSource = Join-Path $RepoRoot 'powertoys\fancyzones'
}

$configFile     = Join-Path $RepoRoot 'config\dev-config.winget'
$m365File       = Join-Path $RepoRoot 'config\m365.winget'
$themeFile      = Join-Path $RepoRoot 'config\theme.winget'
$nativeFile     = Join-Path $RepoRoot 'config\native.winget'
$nativePostFile = Join-Path $RepoRoot 'config\native-post.winget'
$profileLib     = Join-Path $RepoRoot 'lib\Get-MachineProfile.ps1'
$importer       = Join-Path $RepoRoot 'powertoys\Import-FancyZones.ps1'

# Where the post-reboot resume artifacts are written. Deliberately outside the
# repo so a `git clean` cannot strip a pending resume.
$stateDir = Join-Path $env:LOCALAPPDATA 'Windows-Setup'

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }

function Update-SessionPath {
    # Pick up PATH changes made by installers without restarting the shell.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

# Validate-then-apply, the pattern every config in this repo follows.
#
# Emits nothing to the pipeline on purpose: `winget` is a native command, so its
# stdout would otherwise be captured as this function's return value the moment
# a caller assigned it. Callers read the machine state afterwards instead.
function Invoke-WinGetConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path $Path)) { throw "Config not found: $Path" }

    # ADVISORY ONLY - do not gate on this.
    # `winget configure validate` exits 1 for purely informational notes such as
    # "The module was not provided" and "not available publicly", which every
    # unit in these configs produces (upstream's included). Treating non-zero as
    # fatal aborts every run. The real gate is the apply below.
    Write-Step "Validating $Description (advisory)"
    if ($PSCmdlet.ShouldProcess($Path, 'validate')) {
        winget configure validate -f $Path
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    validate exited $LASTEXITCODE - typically warnings only, continuing." -ForegroundColor DarkGray
        }
    }

    Write-Step "Applying $Description"
    if ($PSCmdlet.ShouldProcess($Path, 'apply')) {
        winget configure -f $Path --accept-configuration-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "winget configure exited $LASTEXITCODE for $Description - review the output above."
        }
    }
}

# --- machine detection ---------------------------------------------------------
# Ahead of the elevation check so -DetectOnly works from a normal shell.
if (-not (Test-Path $profileLib)) {
    throw "Detection library not found: $profileLib"
}
. $profileLib

$machine = Get-MachineProfile
if ($Mode -eq 'Auto') { $effectiveMode = $machine.Mode } else { $effectiveMode = $Mode }

Show-MachineProfile -Machine $machine -EffectiveMode $effectiveMode

if ($DetectOnly) {
    Write-Host '  -DetectOnly: nothing was changed.' -ForegroundColor DarkGray
    Write-Host ''
    return
}

if ($effectiveMode -eq 'Native' -and -not $machine.VirtAvailable) {
    Write-Warning @'
Native mode selected but no virtualization extensions are visible. WSL and
Docker Desktop will very likely fail. Enable virtualization in firmware (or
nested virtualization on the host), or run with -Mode Parallels to skip them.
'@
}

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
        '-Mode', $effectiveMode
        '-NoElevate'
    )
    if ($SkipProvision)  { $fwd += '-SkipProvision' }
    if ($SkipFancyZones) { $fwd += '-SkipFancyZones' }
    if ($M365)           { $fwd += '-M365' }
    if ($DarkTheme)      { $fwd += '-DarkTheme' }
    if ($NoReboot)       { $fwd += '-NoReboot' }
    if ($Resume)         { $fwd += '-Resume' }
    if ($WhatIfPreference) { $fwd += '-WhatIf' }

    & $sudo.Source $shell @fwd
    exit $LASTEXITCODE
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store first.'
}

# --- post-reboot resume --------------------------------------------------------
# Escapes a single quote for embedding in a single-quoted PowerShell literal, so
# a home directory containing an apostrophe cannot break the generated script.
function ConvertTo-PSLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

function Register-ResumeAfterReboot {
    param([Parameter(Mandatory)][string]$Root)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        $shellPath = (Get-Command pwsh).Source
    } else {
        $shellPath = (Get-Command powershell).Source
    }

    $bootstrapPath = Join-Path $Root 'bootstrap.ps1'
    $resumePs1     = Join-Path $stateDir 'resume.ps1'
    $resumeCmd     = Join-Path $stateDir 'resume.cmd'

    # RunOnce fires unelevated at logon, and its value has a length ceiling and
    # its own quoting rules. So the registry value is one short path to a .cmd,
    # the .cmd calls a .ps1, and the .ps1 does the -Verb RunAs elevation. Two
    # tiny files instead of one unreadable, length-limited command line.
    $resumeBody = @"
`$ErrorActionPreference = 'Stop'
Start-Process -FilePath '$(ConvertTo-PSLiteral $shellPath)' -Verb RunAs -ArgumentList @(
    '-NoExit'
    '-ExecutionPolicy', 'Bypass'
    '-File', '$(ConvertTo-PSLiteral $bootstrapPath)'
    '-RepoRoot', '$(ConvertTo-PSLiteral $Root)'
    '-Mode', 'Native'
    '-Resume'
)
"@
    Set-Content -LiteralPath $resumePs1 -Value $resumeBody -Encoding UTF8

    $cmdBody = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$resumePs1`""
    Set-Content -LiteralPath $resumeCmd -Value $cmdBody -Encoding ASCII

    # Windows deletes a RunOnce value before executing it, so this cannot fire
    # twice on its own and needs no cleanup step.
    $runOnce = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    if (-not (Test-Path $runOnce)) { New-Item -Path $runOnce -Force | Out-Null }
    Set-ItemProperty -Path $runOnce -Name 'WindowsSetupResume' -Value "`"$resumeCmd`"" -Force

    Write-Host "    resume registered: $resumeCmd" -ForegroundColor DarkGray
}

if ($Resume) {
    Write-Step 'Resuming after reboot - the base provision already ran'
    # The RunOnce value is gone by now; clear the scripts it pointed at.
    Remove-Item -LiteralPath (Join-Path $stateDir 'resume.cmd') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $stateDir 'resume.ps1') -Force -ErrorAction SilentlyContinue
}

# ~/git is where every repo lives. The config declares this too, but do it here
# unconditionally so it never depends on a DSC resource resolving.
if (-not $Resume) {
    $workspace = Join-Path $env:USERPROFILE 'git'
    if (Test-Path $workspace -PathType Leaf) {
        throw "A file exists at $workspace - move it before provisioning."
    }
    if (-not (Test-Path $workspace -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($workspace, 'Create workspace directory')) {
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null
            Write-Step "Created workspace: $workspace"
        }
    }
}

# --- provision ----------------------------------------------------------------
if (-not $Resume -and -not $SkipProvision) {
    if (-not (Test-Path $configFile)) { throw "Config not found: $configFile" }

    # `winget configure --enable` first pulls any pending App Installer update
    # from the Microsoft Store and does not complete until that lands - which
    # looks exactly like a silent hang. Get the update out of the way first.
    # A non-zero exit here just means "already current", so it is not checked.
    # --source winget is deliberate: left implicit, winget resolves this through
    # msstore. Every package in this repo is winget-sourced; this keeps the one
    # bootstrap-time dependency on the same footing.
    Write-Step 'Ensuring App Installer is current (winget source, not msstore)'
    if ($PSCmdlet.ShouldProcess('Microsoft.AppInstaller', 'upgrade')) {
        winget upgrade --id Microsoft.AppInstaller --source winget `
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

    # Microsoft.DSC.Transitional/PowerShellScript is declared with
    # condition "[not(equals(tryWhich('pwsh'), null()))]" and runs via pwsh. On a
    # bare machine pwsh does not exist yet, so every unit of that type reports
    # "Resource not found" - the Cascadia font units, ps7default, the Copilot
    # profile, the WinUI templates. This config INSTALLS PowerShell 7, so a
    # second pass in a process that can see pwsh makes them resolve.
    $pwshBefore = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)

    Invoke-WinGetConfig -Path $configFile -Description 'base configuration (this takes a while)'

    if ($PSCmdlet.ShouldProcess($configFile, 'apply')) {
        Update-SessionPath
        $pwshAfter = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)

        if (-not $pwshBefore -and $pwshAfter) {
            Write-Step 'PowerShell 7 was just installed - re-applying so pwsh-dependent units run'
            winget configure -f $configFile --accept-configuration-agreements --disable-interactivity
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Second pass exited $LASTEXITCODE - review the output above."
            }
        } elseif (-not $pwshAfter) {
            Write-Warning @"
pwsh is still not available. Units of type Microsoft.DSC.Transitional/PowerShellScript
will not have run. Open a NEW elevated shell and re-run: .\bootstrap.ps1
"@
        }
    }
} elseif (-not $Resume) {
    Write-Step 'Skipping provision (-SkipProvision)'
}

# --- M365 (opt-in) ------------------------------------------------------------
# Kept in a separate config so the base provision stays lean. Microsoft 365 Apps
# is a large Click-to-Run download and will dominate this step's runtime.
if (-not $Resume) {
    if ($M365) {
        Invoke-WinGetConfig -Path $m365File -Description 'OneDrive and Microsoft 365 Apps (large download)'
    } else {
        Write-Step 'Skipping M365 (pass -m365 to install OneDrive + Microsoft 365 Apps)'
    }
}

# --- dark theme (opt-in) ------------------------------------------------------
# Was unconditional in dev-config.winget until it moved to config\theme.winget.
if (-not $Resume) {
    if ($DarkTheme) {
        Invoke-WinGetConfig -Path $themeFile -Description 'dark theme'
    } else {
        Write-Step 'Leaving the Windows theme alone (pass -DarkTheme to force dark mode)'
    }
}

# --- Windows Terminal -----------------------------------------------------------
if (-not $Resume) {
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
}

# --- FancyZones ---------------------------------------------------------------
# No early `return` in here: the Native section below still has to run.
if ($Resume) {
    # nothing - FancyZones ran before the reboot
} elseif ($SkipFancyZones) {
    Write-Step 'Skipping FancyZones (-SkipFancyZones)'
} else {
    Write-Step 'Configuring FancyZones'

    $layouts = Join-Path $FancyZonesSource 'custom-layouts.json'
    if (-not (Test-Path $layouts)) {
        Write-Warning @"
No custom-layouts.json in $FancyZonesSource
Copy these off the other workstation's %LOCALAPPDATA%\Microsoft\PowerToys\FancyZones:
  custom-layouts.json  layout-hotkeys.json  layout-templates.json  default-layouts.json
then re-run:  .\bootstrap.ps1 -SkipProvision
"@
    } else {
        $importArgs = @{ SourcePath = $FancyZonesSource }
        if ($PSBoundParameters.ContainsKey('WhatIf')) { $importArgs['WhatIf'] = $true }
        & $importer @importArgs
    }
}

# --- Native extras ------------------------------------------------------------
# Last on purpose. This is the only section that can reboot the machine, and
# putting it after everything else means an interrupted resume costs the WSL and
# Docker half rather than the entire provision.
if ($effectiveMode -ne 'Native') {
    Write-Step 'Parallels mode - skipping WSL, Docker, Hyper-V and Windows Sandbox'
    Write-Step 'Done'
    return
}

if ($SkipProvision -and -not $Resume) {
    Write-Step 'Skipping the native overlay too (-SkipProvision)'
    Write-Step 'Done'
    return
}

if (-not $Resume) {
    Invoke-WinGetConfig -Path $nativeFile `
        -Description 'native overlay: virtualization features and WSL components'
}

# vmcompute (Hyper-V Host Compute Service) is registered once Virtual Machine
# Platform is actually active, which only happens after a reboot. It is the same
# test the WSL units use, and the gate for the post-reboot half.
$vmcompute = [bool](Get-CimInstance -ClassName Win32_Service -Filter "Name='vmcompute'" `
                       -ErrorAction SilentlyContinue)

if (-not $vmcompute) {
    if ($Resume) {
        Write-Warning @'
Resumed after the reboot but Virtual Machine Platform still is not active
(no vmcompute service). WSL cannot install. Check that virtualization is enabled
in firmware, then re-run:  .\bootstrap.ps1 -SkipProvision
'@
        return
    }

    if ($NoReboot) {
        Write-Step 'WSL components installed - reboot required (-NoReboot given, not rebooting)'
        Write-Host '    Reboot, then finish with:  .\bootstrap.ps1 -Resume' -ForegroundColor Yellow
        return
    }

    if (-not $PSCmdlet.ShouldProcess('this machine', 'Restart to activate Virtual Machine Platform')) {
        Write-Step 'Would reboot here to activate Virtual Machine Platform'
        return
    }

    Write-Step 'Reboot required to activate Virtual Machine Platform'
    Register-ResumeAfterReboot -Root $RepoRoot

    Write-Host ''
    Write-Warning 'Rebooting in 20 seconds. Ubuntu and Docker Desktop install automatically after you log back in (expect one UAC prompt).'
    Write-Host '    Press Ctrl+C to cancel - re-run with -Resume once you have rebooted yourself.' -ForegroundColor DarkGray
    for ($i = 20; $i -gt 0; $i--) {
        Write-Host -NoNewline ("`r    rebooting in {0,2}s ... " -f $i)
        Start-Sleep -Seconds 1
    }
    Write-Host ''
    Restart-Computer -Force
    return
}

Invoke-WinGetConfig -Path $nativePostFile `
    -Description 'native overlay: Ubuntu distro and Docker Desktop'

Write-Host ''
Write-Host '  Docker Desktop adds you to the docker-users group - sign out and back in' -ForegroundColor DarkGray
Write-Host '  before first use. Set the Ubuntu UNIX user with:  wsl -d Ubuntu' -ForegroundColor DarkGray

Write-Step 'Done'
