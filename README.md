# Windows-Setup

Repeatable provisioning for a Windows 11 dev box (running as a Parallels guest).

Wraps [microsoft/WindowsDeveloperConfig](https://github.com/microsoft/WindowsDeveloperConfig)
with the WSL phases removed, plus FancyZones layout import.

> Public repo. Run `.\Test-Clean.ps1` before every push — see
> [Public repo hygiene](#public-repo-hygiene).

## Quick start

From an **elevated** PowerShell:

```powershell
git clone https://github.com/floatingsidewal/Windows-Setup.git ~/git/Windows-Setup
cd ~/git/Windows-Setup
.\bootstrap.ps1 -WhatIf     # dry run
.\bootstrap.ps1
```

## Layout

```
config/
  dev-config.winget            # what actually runs - WSL removed
  dev-config.upstream.winget   # pristine upstream copy, for diffing on update
powertoys/
  Import-FancyZones.ps1        # enables FancyZones, imports layouts, overrides snap
  fancyzones/                  # drop custom-layouts.json etc. here (see below)
dotfiles/                      # gitconfig, PS profile, Terminal settings
bootstrap.ps1                  # provision + FancyZones in one shot
```

## What's different from upstream

**WSL Phases 1-3 are removed.** This is a Parallels guest, so nested virt is a
non-starter — and upstream's Phase 2 (`RebootForVmp`) calls `Restart-Computer
-Force` mid-run, rebooting the machine to activate Virtual Machine Platform.
Nothing else in the file had a `dependsOn` pointing at the WSL resources, so it
cuts cleanly (962 → 909 lines).

Everything else upstream installs is kept: Windows Terminal, PowerShell 7, Git,
GitHub CLI + Copilot, VS Code, .NET SDK 10, Python 3.14 + uv, Node LTS + NVM,
Coreutils, Oh My Posh, PowerToys, Cascadia Code Nerd Fonts, and the Windows
registry tweaks.

Two of those tweaks are worth knowing about:

- `DoNotDisturb` sets `NOC_GLOBAL_SETTING_TOASTS_ENABLED=0` — silences **all**
  Windows notifications.
- `RemoteDesktop` sets `fDenyTSConnections=0` — enables RDP.

Delete those resource blocks from `config/dev-config.winget` if unwanted.

Upstream's `ElevationCheck` (Phase 0) is commented out, so nothing self-elevates.
Run from an admin prompt.

## FancyZones

`Import-FancyZones.ps1` stops PowerToys, backs up the current config, copies in
layout files, sets three settings, and restarts it:

| Setting | Effect |
| --- | --- |
| `fancyzones_overrideSnapHotkeys` | Win+Arrow moves between zones |
| `fancyzones_moveWindowsBasedOnPosition` | Relative position — overrides **all four** arrows, enables Win+Ctrl+Alt+Arrow to span zones |
| `fancyzones_moveWindowAcrossMonitors` | Arrows cycle across all monitors |

Without `moveWindowsBasedOnPosition`, only Win+Left / Win+Right get overridden
and Win+Up / Win+Down keep native Windows behavior.

### Populating `powertoys/fancyzones/`

Copy these from the source machine's `%LOCALAPPDATA%\Microsoft\PowerToys\FancyZones`:

- `custom-layouts.json` — the layouts
- `layout-hotkeys.json` — Win+Ctrl+Alt+`<n>` bindings
- `layout-templates.json` — tweaks to built-in templates
- `default-layouts.json` — default layout per monitor orientation

**Not** `applied-layouts.json` or `app-zone-history.json` — they're keyed to
monitor hardware IDs and won't match a different display. They're gitignored.
After importing, assign a layout to the display once via **Win+Shift+`**.
Setting a default per orientation makes it stick automatically when the
Parallels display resolution changes.

## Public repo hygiene

Everything here resolves paths at runtime via `$PSScriptRoot` and
`$env:LOCALAPPDATA`, so no username or home path is baked into any file.
Keep it that way:

```powershell
.\Test-Clean.ps1     # scans for usernames, home paths, emails, tokens, keys
```

It exits non-zero on findings, so it works as a pre-commit hook:

```powershell
"pwsh -NoProfile -File `"$PWD\Test-Clean.ps1`" || exit 1" |
  Set-Content .git\hooks\pre-commit -Encoding utf8
```

Two FancyZones files are gitignored specifically because they identify hardware,
not just because they don't transfer:

- `applied-layouts.json` embeds monitor device IDs, **including display serial numbers**
- `app-zone-history.json` embeds full exe paths, **including `C:\Users\<username>`**

`dotfiles/` is the highest-risk directory — see [dotfiles/README.md](dotfiles/README.md).
Commit `*.template` files with placeholders, never the real thing.

`Test-Clean.ps1` scans the **working tree, not git history**. If something
sensitive already landed in a commit, deleting it in a later commit does not
remove it — rewrite history and rotate the credential.

## Updating from upstream

```powershell
curl -o config/dev-config.upstream.winget `
  https://raw.githubusercontent.com/microsoft/WindowsDeveloperConfig/main/windows-dev-config/dev-config.winget
git diff config/dev-config.upstream.winget
```

Then port any wanted changes into `config/dev-config.winget` by hand.
