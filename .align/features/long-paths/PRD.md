---
status: complete
updated: 2026-09-05
---

# PRD: long-paths

## Execution Rules

1. If the user names a task, execute it after verifying dependencies.
2. Otherwise choose the lowest-numbered unchecked dependency-ready task.
3. Read SYSTEM.md, FEATURE.md, and DESIGN.md before execution.
4. Complete a task only after directly verifying acceptance.
5. Record one concise Evidence line on the completed task.

## Status

| Milestone | Status | Tasks |
|-----------|--------|-------|
| 1. Enforce long-path policy | Complete | 1/1 |

## Milestone 1: Enforce long-path policy

**Goal:** Make every mutating bootstrap run enforce Win32 long-path support.
**Depends on:** None
**Governing decisions:** SYS-1, SYS-3, LP-1, LP-2, LP-3

### Tasks

- [x] **1.1 Enforce long-path support during bootstrap**
  - Scope: Add an idempotent registry configuration script, invoke it outside
    winget provisioning, document the behavior, and add focused verification.
  - Files: `dotfiles\Configure-LongPaths.ps1`, `bootstrap.ps1`,
    `tests\Test-LongPaths.ps1`, `README.md`
  - Governing decisions: SYS-1, SYS-3, LP-1, LP-2, LP-3
  - Acceptance: Run `pwsh -NoProfile -File tests\Test-LongPaths.ps1`;
    `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-LongPaths.ps1`;
    and `pwsh -NoProfile -File Test-Clean.ps1`.
  - Evidence: PowerShell 7 and Windows PowerShell 5.1 verified missing,
    enabled, idempotent, `-WhatIf`, parser, and bootstrap-integration behavior;
    `Test-Clean.ps1` reported a clean working tree.

### Milestone Outcome

Bootstrap now enforces `LongPathsEnabled = 1` immediately after elevation,
independently of winget provisioning, and verifies every write. PowerShell 7,
Windows PowerShell 5.1, and the public-repo cleanliness scan passed.
