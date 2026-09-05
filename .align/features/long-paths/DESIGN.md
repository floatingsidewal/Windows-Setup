# Design: Win32 Long Paths

## Context

`config\dev-config.winget` already declares `LongPathsEnabled`, but that resource
only runs during the base winget provisioning pass. Bootstrap also supports
repair and resume modes that bypass that pass.

## Architecture

A focused `dotfiles\Configure-LongPaths.ps1` script reads the machine policy,
writes DWORD `1` only when needed, and reads it back to verify success.
`bootstrap.ps1` invokes the script immediately after elevation and before any
winget dependency check.

## Interfaces and Data Flow

- Production input: `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem` and
  value `LongPathsEnabled`.
- Test input: an isolated current-user registry path.
- Persistent output: DWORD `LongPathsEnabled = 1`.

## Decisions

- **LP-1:** Keep the winget registry resource as declarative defense in depth,
  but do not depend on winget for this baseline policy.
- **LP-2:** Treat a failed write or failed read-back as a terminating setup
  error.
- **LP-3:** Allow an explicit registry path and value name so behavior can be
  verified without modifying the machine policy during tests.

## Failure Behavior

Registry access and write failures terminate setup. A successful command whose
read-back is not DWORD `1` also terminates setup.

## Security and Privacy

The production write targets one documented machine policy value. Tests use an
isolated current-user key and remove it afterward.

## Verification Strategy

- Parse every tracked PowerShell script.
- Exercise missing, enabled, idempotent, and `-WhatIf` behavior in an isolated
  current-user registry key under PowerShell 7 and Windows PowerShell 5.1.
- Verify bootstrap integration and run `Test-Clean.ps1`.

## Open Questions

None.
