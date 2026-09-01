# Feature: Local PowerShell Storage

## Problem

Enterprise policy can redirect the Documents known folder into OneDrive.
PowerShell then places profiles and current-user modules in synchronized
folders, which can delay shell startup and module discovery.

## Outcome

Windows PowerShell and PowerShell 7 profile/module directories physically live
under the user's unsynchronized local application data while their standard
Documents paths remain available through directory junctions.

## Users

Developers provisioning a Windows machine with this repository.

## Requirements

- Migrate existing `Documents\WindowsPowerShell` and `Documents\PowerShell`
  content without deleting the source before a successful copy.
- Create junctions from the standard Documents paths to local application data.
- Leave correctly configured junctions unchanged on repeated runs.
- Refuse to replace an existing reparse point that targets another location.
- Persist module search paths that prefer the local module directories.
- Run automatically during normal bootstrap and support `-WhatIf`.

## Non-Goals

- Changing the enterprise Documents redirection policy.
- Moving unrelated Documents content out of OneDrive.
- Repairing arbitrary symbolic links or junctions owned by other tools.

## Success Criteria

- A normal bootstrap invokes the focused configuration script.
- Existing profile data is retained at the local destination.
- Both standard Documents directories resolve to their matching local
  application data directories.
- Re-running the script performs no migration when the junctions are correct.
