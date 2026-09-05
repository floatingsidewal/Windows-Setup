[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'dotfiles\Configure-LongPaths.ps1'
$bootstrapPath = Join-Path $root 'bootstrap.ps1'
$testRoot = "HKCU:\Software\WindowsSetup\Tests\LongPaths-$PID"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

try {
    $parseErrors = @()
    $powerShellScripts = Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse |
        Where-Object { $_.FullName -notmatch '\\\.git\\' }

    foreach ($powerShellScript in $powerShellScripts) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $powerShellScript.FullName,
            [ref]$tokens,
            [ref]$errors)
        $parseErrors += $errors
    }
    Assert-True ($parseErrors.Count -eq 0) "PowerShell parse errors:`n$($parseErrors -join "`n")"

    & $scriptPath -RegistryPath $testRoot
    Assert-True ((Get-ItemPropertyValue -LiteralPath $testRoot -Name LongPathsEnabled) -eq 1) `
        'The missing policy was not enabled.'

    & $scriptPath -RegistryPath $testRoot
    Assert-True ((Get-ItemPropertyValue -LiteralPath $testRoot -Name LongPathsEnabled) -eq 1) `
        'The enabled policy changed on a repeated run.'

    Set-ItemProperty -LiteralPath $testRoot -Name LongPathsEnabled -Value 0
    & $scriptPath -RegistryPath $testRoot -WhatIf
    Assert-True ((Get-ItemPropertyValue -LiteralPath $testRoot -Name LongPathsEnabled) -eq 0) `
        '-WhatIf changed the policy.'

    $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    $invokeIndex = $bootstrap.IndexOf('& $longPathsScript @longPathsArgs')
    $wingetIndex = $bootstrap.IndexOf("if (-not (Get-Command winget")
    Assert-True ($invokeIndex -ge 0) 'Bootstrap does not invoke Configure-LongPaths.ps1.'
    Assert-True ($wingetIndex -ge 0 -and $invokeIndex -lt $wingetIndex) `
        'Long-path configuration must run before the winget availability check.'

    Write-Host 'Long-path configuration tests passed.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
