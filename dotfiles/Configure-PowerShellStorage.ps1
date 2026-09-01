<#
.SYNOPSIS
  Keeps PowerShell profiles and current-user modules out of redirected
  Documents storage.

.DESCRIPTION
  Migrates the Windows PowerShell and PowerShell 7 directories from the
  Documents known folder into LocalAppData, then replaces the standard
  Documents paths with directory junctions.

  Existing source content is copied before the source directory is removed.
  Copy errors are terminating, so a failed migration leaves the source intact.

.PARAMETER LocalAppDataPath
  Physical parent for the local PowerShell directories. Defaults to
  %LOCALAPPDATA%.

.PARAMETER DocumentsPath
  Documents known folder containing WindowsPowerShell and PowerShell.

.PARAMETER ModulePathTarget
  Environment-variable target for PSModulePath. User is the normal persistent
  setup behavior; Process is intended for isolated verification.

.EXAMPLE
  .\Configure-PowerShellStorage.ps1
  .\Configure-PowerShellStorage.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LocalAppDataPath = $env:LOCALAPPDATA,
    [string]$DocumentsPath = [Environment]::GetFolderPath('MyDocuments'),

    [ValidateSet('User', 'Process')]
    [string]$ModulePathTarget = 'User'
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    try {
        return [IO.Path]::GetFullPath($expandedPath).TrimEnd('\')
    } catch [ArgumentException], [NotSupportedException] {
        # Preserve unusual provider-qualified module paths rather than failing
        # the entire setup while comparing them with filesystem paths.
        return $expandedPath.TrimEnd('\')
    }
}

function Test-SamePath {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )

    return [string]::Equals(
        (Get-NormalizedPath $Left),
        (Get-NormalizedPath $Right),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        throw "A file exists where a directory is required: $Path"
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container) -and
        $PSCmdlet.ShouldProcess($Path, 'Create local PowerShell directory')) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    }
}

function Assert-NoCopyConflict {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $sourceRoot = (Get-NormalizedPath $SourcePath) + '\'
    foreach ($sourceItem in Get-ChildItem -LiteralPath $SourcePath -Recurse -Force) {
        $relativePath = $sourceItem.FullName.Substring($sourceRoot.Length)
        $destinationItemPath = Join-Path $DestinationPath $relativePath

        if ($sourceItem.PSIsContainer) {
            if (Test-Path -LiteralPath $destinationItemPath -PathType Leaf) {
                throw "Cannot migrate $($sourceItem.FullName): a file exists at $destinationItemPath"
            }
            continue
        }

        if (Test-Path -LiteralPath $destinationItemPath -PathType Container) {
            throw "Cannot migrate $($sourceItem.FullName): a directory exists at $destinationItemPath"
        }
        if (-not (Test-Path -LiteralPath $destinationItemPath -PathType Leaf)) {
            continue
        }

        $destinationItem = Get-Item -LiteralPath $destinationItemPath -Force
        $sameLength = $sourceItem.Length -eq $destinationItem.Length
        $sameHash = $sameLength -and
            ((Get-FileHash -LiteralPath $sourceItem.FullName -Algorithm SHA256).Hash -eq
             (Get-FileHash -LiteralPath $destinationItemPath -Algorithm SHA256).Hash)

        if (-not $sameHash) {
            throw "Cannot migrate $($sourceItem.FullName): different content exists at $destinationItemPath"
        }
    }
}

function Set-DirectoryJunction {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Label
    )

    if (Test-Path -LiteralPath $LinkPath) {
        $existing = Get-Item -LiteralPath $LinkPath -Force

        if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $targets = @($existing.Target)
            if ($targets.Count -eq 1 -and
                (Test-SamePath ([string]$targets[0]) $TargetPath)) {
                Write-Host "$Label already points to local storage." -ForegroundColor DarkGray
                return
            }

            throw "$LinkPath is already a reparse point with an unexpected target: $($targets -join ', ')"
        }

        if (-not $existing.PSIsContainer) {
            throw "A file exists where the $Label directory is required: $LinkPath"
        }

        if ($PSCmdlet.ShouldProcess($LinkPath, "Copy existing $Label content to $TargetPath")) {
            Assert-NoCopyConflict -SourcePath $LinkPath -DestinationPath $TargetPath
            $children = @(Get-ChildItem -LiteralPath $LinkPath -Force)
            foreach ($child in $children) {
                Copy-Item -LiteralPath $child.FullName -Destination $TargetPath `
                    -Recurse -Force -ErrorAction Stop
            }

            Remove-Item -LiteralPath $LinkPath -Recurse -Force -ErrorAction Stop
        } else {
            return
        }
    }

    if ($PSCmdlet.ShouldProcess($LinkPath, "Create junction to $TargetPath")) {
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath `
            -ErrorAction Stop | Out-Null
        Write-Host "$Label redirected to $TargetPath" -ForegroundColor Green
    }
}

function Set-LocalModulePath {
    param(
        [Parameter(Mandatory)][string[]]$RedirectedPaths,
        [Parameter(Mandatory)][string[]]$LocalPaths,
        [Parameter(Mandatory)][ValidateSet('User', 'Process')]
        [string]$Target
    )

    $candidates = @(
        $LocalPaths
        [Environment]::GetEnvironmentVariable('PSModulePath', $Target)
        [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
        if ($Target -eq 'User') {
            [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
        }
    )

    $cleanPaths = New-Object System.Collections.Generic.List[string]
    foreach ($candidateSet in $candidates) {
        foreach ($candidate in @($candidateSet -split ';')) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

            $isRedirected = $false
            foreach ($redirectedPath in $RedirectedPaths) {
                if (Test-SamePath $candidate $redirectedPath) {
                    $isRedirected = $true
                    break
                }
            }
            if ($isRedirected) { continue }

            $alreadyAdded = $false
            foreach ($existingPath in $cleanPaths) {
                if (Test-SamePath $existingPath $candidate) {
                    $alreadyAdded = $true
                    break
                }
            }
            if (-not $alreadyAdded) { $cleanPaths.Add($candidate) }
        }
    }

    $newValue = $cleanPaths -join ';'
    $currentValue = [Environment]::GetEnvironmentVariable('PSModulePath', $Target)
    if ($newValue -eq $currentValue) {
        Write-Host "PSModulePath ($Target) already uses local PowerShell storage." -ForegroundColor DarkGray
        return
    }

    if ($PSCmdlet.ShouldProcess("PSModulePath ($Target)", 'Use local PowerShell module directories')) {
        [Environment]::SetEnvironmentVariable('PSModulePath', $newValue, $Target)
        Write-Host "PSModulePath ($Target) updated." -ForegroundColor Green
    }
}

if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
    throw 'LocalAppDataPath could not be resolved.'
}
if ([string]::IsNullOrWhiteSpace($DocumentsPath)) {
    throw 'DocumentsPath could not be resolved.'
}

$localWinPSDir = Join-Path $LocalAppDataPath 'WindowsPowerShell'
$localPwshDir = Join-Path $LocalAppDataPath 'PowerShell'
$documentsWinPSDir = Join-Path $DocumentsPath 'WindowsPowerShell'
$documentsPwshDir = Join-Path $DocumentsPath 'PowerShell'

Ensure-Directory $localWinPSDir
Ensure-Directory $localPwshDir

Set-DirectoryJunction -LinkPath $documentsWinPSDir `
    -TargetPath $localWinPSDir -Label 'Windows PowerShell storage'
Set-DirectoryJunction -LinkPath $documentsPwshDir `
    -TargetPath $localPwshDir -Label 'PowerShell storage'

$redirectedModulePaths = @(
    (Join-Path $documentsWinPSDir 'Modules')
    (Join-Path $documentsPwshDir 'Modules')
)
$localModulePaths = @(
    (Join-Path $localWinPSDir 'Modules')
    (Join-Path $localPwshDir 'Modules')
)

Set-LocalModulePath -RedirectedPaths $redirectedModulePaths `
    -LocalPaths $localModulePaths -Target $ModulePathTarget

if ($ModulePathTarget -eq 'User') {
    Set-LocalModulePath -RedirectedPaths $redirectedModulePaths `
        -LocalPaths $localModulePaths -Target 'Process'
}
