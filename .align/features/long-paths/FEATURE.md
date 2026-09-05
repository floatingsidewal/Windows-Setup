# Feature: Win32 Long Paths

## Problem

Windows retains the traditional 260-character path limit unless the machine
long-path policy is enabled. The base winget configuration declares the policy,
but bootstrap modes that skip provisioning do not independently verify it.

## Outcome

Every mutating bootstrap run verifies that Win32 long-path support is enabled
and enables it when necessary.

## Users

Developers provisioning or repairing a Windows machine with this repository.

## Requirements

- Check `LongPathsEnabled` after bootstrap has elevated.
- Set the policy to DWORD `1` when it is missing or disabled.
- Verify the value after writing and stop setup if verification fails.
- Run independently of winget provisioning, including `-SkipProvision` and
  post-reboot resume runs.
- Leave an already enabled policy unchanged.
- Support `-WhatIf`.

## Non-Goals

- Making applications opt in to long-path-aware Win32 APIs.
- Changing application manifests or Git-specific long-path settings.
- Removing the declarative registry resource from the winget configuration.

## Success Criteria

- A disabled or missing test policy is set to DWORD `1`.
- Re-running the configuration leaves an enabled policy unchanged.
- `-WhatIf` reports the change without writing it.
- Bootstrap invokes the focused script before winget availability or
  provisioning checks.
