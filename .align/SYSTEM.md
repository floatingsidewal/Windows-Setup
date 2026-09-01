# Windows Setup System

## Purpose

This repository provisions a repeatable Windows development machine from the
public `install.ps1` entry point and the elevated `bootstrap.ps1` orchestrator.

## Boundaries

- `install.ps1` acquires the repository and launches provisioning.
- `bootstrap.ps1` owns ordering, elevation, mode selection, and reboot flow.
- Focused scripts under `dotfiles\`, `powertoys\`, and `lib\` own individual,
  idempotent configuration changes.
- Configuration must resolve user-specific paths at runtime and remain safe to
  publish.

## Decisions

- **SYS-1:** Focused configuration behavior belongs in a dedicated script and
  is invoked by `bootstrap.ps1`; it is not embedded as a large inline block.
- **SYS-2:** Destructive migration steps must stop on copy errors and preserve
  the original source until copying has completed successfully.
- **SYS-3:** Setup scripts that mutate machine or user state support `-WhatIf`
  where practical.
