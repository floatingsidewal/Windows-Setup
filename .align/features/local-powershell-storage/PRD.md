---
status: complete
updated: 2026-09-01
---

# PRD: local-powershell-storage

## Execution Rules

1. If the user names a task, execute it after verifying dependencies.
2. Otherwise choose the lowest-numbered unchecked dependency-ready task.
3. Read SYSTEM.md, FEATURE.md, and DESIGN.md before execution.
4. Complete a task only after directly verifying acceptance.
5. Record one concise Evidence line on the completed task.

## Status

| Milestone | Status | Tasks |
|-----------|--------|-------|
| 1. Redirect PowerShell storage | Complete | 1/1 |

## Milestone 1: Redirect PowerShell storage

**Goal:** Keep PowerShell profile and module data local on machines whose
Documents folder is redirected.
**Depends on:** None
**Governing decisions:** SYS-1, SYS-2, SYS-3, LPS-1, LPS-2, LPS-3, LPS-4

### Tasks

- [x] **1.1 Configure local PowerShell storage during bootstrap**
  - Scope: Add an idempotent migration/junction script, invoke it from normal
    bootstrap, and document the behavior.
  - Files: `dotfiles\Configure-PowerShellStorage.ps1`, `bootstrap.ps1`,
    `README.md`
  - Governing decisions: SYS-1, SYS-2, SYS-3, LPS-1, LPS-2, LPS-3, LPS-4
  - Acceptance: Parse every tracked PowerShell script; execute the new script
    twice against temporary paths; verify migrated files and junction targets;
    run `Test-Clean.ps1`.
  - Evidence: PowerShell 7 and Windows PowerShell 5.1 parsed every script;
    isolated migration, junction, idempotence, conflict, and WhatIf checks
    passed; `Test-Clean.ps1` reported a clean working tree.

### Milestone Outcome

Bootstrap now migrates both PowerShell profile/module directories from
redirected Documents storage into LocalAppData, preserves existing content,
refuses conflicting data or unexpected reparse points, and leaves idempotent
junctions at the standard paths. Verification passed in PowerShell 7 and
Windows PowerShell 5.1.
