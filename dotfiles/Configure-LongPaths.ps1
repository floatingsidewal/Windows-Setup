<#
.SYNOPSIS
  Ensures Win32 long-path support is enabled.

.DESCRIPTION
  Sets LongPathsEnabled to DWORD 1 when the policy is missing or disabled, then
  reads the value back to verify the change. Repeated runs are idempotent.

.PARAMETER RegistryPath
  Registry key containing the policy. Override only for isolated testing.

.PARAMETER ValueName
  Registry value holding the policy. Override only for isolated testing.

.EXAMPLE
  .\Configure-LongPaths.ps1

.EXAMPLE
  .\Configure-LongPaths.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$RegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem',

    [ValidateNotNullOrEmpty()]
    [string]$ValueName = 'LongPathsEnabled'
)

$ErrorActionPreference = 'Stop'

function Get-LongPathsValue {
    $property = Get-ItemProperty -LiteralPath $RegistryPath -Name $ValueName `
        -ErrorAction SilentlyContinue
    if (-not $property) { return $null }

    $value = $property.PSObject.Properties[$ValueName]
    if (-not $value) { return $null }
    return [int]$value.Value
}

$current = Get-LongPathsValue
if ($current -eq 1) {
    Write-Host '    Win32 long-path support is already enabled.' -ForegroundColor DarkGray
    return
}

if (-not $PSCmdlet.ShouldProcess(
        "$RegistryPath\$ValueName",
        'Set DWORD value to 1 to enable Win32 long-path support')) {
    return
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}

New-ItemProperty -LiteralPath $RegistryPath -Name $ValueName `
    -PropertyType DWord -Value 1 -Force | Out-Null

$configured = Get-LongPathsValue
if ($configured -ne 1) {
    throw "Failed to enable Win32 long-path support at $RegistryPath\$ValueName."
}

Write-Host '    Enabled Win32 long-path support.' -ForegroundColor Green
