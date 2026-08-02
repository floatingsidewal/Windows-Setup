<#
.SYNOPSIS
  Pre-publish scan. Fails if anything in the working tree looks like PII,
  a hardware identifier, or a credential.

.DESCRIPTION
  This repo is public. Run before every push. Exits 1 on findings so it can be
  wired up as a pre-commit hook:

    "pwsh -NoProfile -File `"$PWD\Test-Clean.ps1`" || exit 1" |
      Set-Content .git\hooks\pre-commit -Encoding utf8

  Note this scans the working tree, not git history. If a secret was already
  committed, removing it in a new commit is NOT enough - rewrite history and
  rotate the credential.

.EXAMPLE
  .\Test-Clean.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root     = $PSScriptRoot
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param([string]$File, [int]$Line, [string]$Rule, [string]$Text)
    $findings.Add([pscustomobject]@{
        File = $File; Line = $Line; Rule = $Rule
        Text = $Text.Trim()
    })
}

# Built dynamically so this script contains no PII of its own.
$patterns = [ordered]@{
    'current username'   = [regex]::Escape($env:USERNAME)
    'home directory path'= 'C:\\Users\\[A-Za-z0-9._-]+'
    'unix home path'     = '/(?:home|Users)/[A-Za-z0-9._-]+'
    'email address'      = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    'GitHub token'       = 'gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}'
    'AWS access key'     = 'AKIA[0-9A-Z]{16}'
    'Slack token'        = 'xox[baprs]-[A-Za-z0-9-]{10,}'
    'private key block'  = '-----BEGIN (?:RSA |OPENSSH |EC |PGP )?PRIVATE KEY'
    'bearer/secret assign' = '(?i)\b(?:api[_-]?key|secret|password|passwd|token)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{12,}'
}

# Files that must never be tracked at all, regardless of content.
$forbiddenNames = @(
    'applied-layouts.json'   # embeds monitor device IDs incl. display serials
    'app-zone-history.json'  # embeds full exe paths incl. C:\Users\<name>
)

$files = Get-ChildItem $root -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }

foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')

    if ($forbiddenNames -contains $f.Name) {
        Add-Finding $rel 0 'forbidden file' $f.Name
        continue
    }

    # Skip binaries.
    if ($f.Extension -in '.png','.jpg','.ico','.zip','.exe','.dll','.ttf',
                         '.mp3','.wav','.m4a') { continue }

    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        foreach ($rule in $patterns.Keys) {
            # The .gitignore documents these patterns on purpose - don't flag it.
            if ($rel -eq '.gitignore' -or $rel -eq 'Test-Clean.ps1') { continue }
            if ($line -match $patterns[$rule]) {
                Add-Finding $rel $lineNo $rule $line
            }
        }
    }
}

if ($findings.Count -eq 0) {
    Write-Host 'Clean - nothing identifying found in the working tree.' -ForegroundColor Green
    exit 0
}

Write-Host "Found $($findings.Count) issue(s):`n" -ForegroundColor Red
$findings | Format-Table -AutoSize File, Line, Rule, Text | Out-String | Write-Host
Write-Host 'Resolve these before pushing to a public repo.' -ForegroundColor Red
exit 1
