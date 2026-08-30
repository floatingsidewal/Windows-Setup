<#
.SYNOPSIS
  Restores the classic File Explorer context menu on Windows 11.

.DESCRIPTION
  Creates the empty InprocServer32 default value used by Explorer to bypass the
  Windows 11 compact context menu. Restarts Explorer only when the registry
  setting needs to change.

.EXAMPLE
  .\Configure-Explorer.ps1
  .\Configure-Explorer.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$relativeKey = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
$registryKey = "HKCU:\$relativeKey"

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($relativeKey)
try {
    $configured = $key -and
        ($key.GetValueNames() -contains '') -and
        ([string]$key.GetValue('') -eq '')
} finally {
    if ($key) { $key.Dispose() }
}

if ($configured) {
    Write-Host 'Classic Explorer context menu is already enabled.' -ForegroundColor DarkGray
    return
}

if (-not $PSCmdlet.ShouldProcess($registryKey, 'Enable classic Explorer context menu')) {
    return
}

& reg.exe add 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /f /ve
if ($LASTEXITCODE -ne 0) {
    throw "reg.exe failed to enable the classic Explorer context menu (exit $LASTEXITCODE)."
}

Write-Host 'Classic Explorer context menu enabled. Restarting Explorer...' -ForegroundColor Green

$explorerProcesses = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
foreach ($process in $explorerProcesses) {
    Stop-Process -Id $process.Id -Force
}

Start-Sleep -Milliseconds 500
if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
    Start-Process explorer.exe
}
