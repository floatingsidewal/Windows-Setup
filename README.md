# Windows-Setup

Repeatable provisioning for a Windows 11 dev box (running as a Parallels guest).

Wraps [microsoft/WindowsDeveloperConfig](https://github.com/microsoft/WindowsDeveloperConfig)
with the WSL phases removed, plus FancyZones layout import.

> Public repo. Run `.\Test-Clean.ps1` before every push — see
> [Public repo hygiene](#public-repo-hygiene).

## Quick start

On a bare machine, from a **normal (unelevated)** PowerShell:

```powershell
irm https://raw.githubusercontent.com/floatingsidewal/Windows-Setup/main/install.ps1 | iex
```

That installs git if missing, creates `~/git`, clones this repo, and elevates
into `bootstrap.ps1`. Run it unelevated — it elevates only for provisioning, and
it elevates a local file rather than re-piping remote code into an admin shell.

### Prerequisites

Only two commands are assumed to have run first:

```powershell
sudo config --enable normal            # inline elevation
Set-ExecutionPolicy RemoteSigned       # allow local scripts
```

`RemoteSigned` is enough: `irm | iex` isn't governed by execution policy at all
(it's never a file on disk), and `git clone` doesn't apply mark-of-the-web to
what it writes, so the cloned scripts run without needing `Unblock-File`.

`install.ps1` prefers `sudo` for inline elevation so provisioning output stays
in one window, and falls back to a separate elevated window if `sudo` is
unavailable.

### Full sequence on a fresh install

1. **Prerequisites**, from a normal unelevated PowerShell:

   ```powershell
   sudo config --enable normal
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

   `-Scope CurrentUser` matters — with no scope, `Set-ExecutionPolicy` targets
   `LocalMachine` and fails unelevated.

2. **Run the installer**, still unelevated. Expect a UAC prompt when it elevates:

   ```powershell
   irm https://raw.githubusercontent.com/floatingsidewal/Windows-Setup/main/install.ps1 | iex
   ```

   Installs git, creates `~/git`, clones, elevates into `bootstrap.ps1`, applies
   the winget config, then imports FancyZones and starts PowerToys. Single pass.
   This is the long step.

3. **Assign a layout** — <kbd>Win</kbd>+<kbd>Shift</kbd>+<kbd>`</kbd> opens the
   editor. Pick an imported layout for the display, then verify:

   - Win+Left / Right / Up / Down move between zones
   - Win+Ctrl+Alt+0 / 1 / 4 apply the three layouts
   - Win+Ctrl+Alt+Arrow spans a window across zones

   Layout-to-monitor assignment is the one genuinely manual step: it's keyed to
   monitor hardware IDs, so it can't be imported.

### Optional: Microsoft 365

OneDrive and Microsoft 365 Apps are **not** installed by default. Opt in with
`-m365`:

```powershell
cd ~/git/Windows-Setup
.\bootstrap.ps1 -m365
```

`irm | iex` can't take arguments, so from the one-liner build a scriptblock:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/floatingsidewal/Windows-Setup/main/install.ps1))) -m365
```

They live in `config/m365.winget` and can also be applied standalone:

```powershell
winget configure -f config\m365.winget --accept-configuration-agreements --disable-interactivity
```

Microsoft 365 Apps is a large Click-to-Run download and will dominate the
runtime of a `-m365` pass.

### Already cloned

```powershell
cd ~/git/Windows-Setup
.\bootstrap.ps1 -WhatIf     # dry run
.\bootstrap.ps1             # needs elevation
```

Re-running `install.ps1` on an existing clone does a `git pull --ff-only`, so
local commits are never silently discarded.

## Layout

```
install.ps1                    # irm | iex entry point: git -> clone -> elevate
bootstrap.ps1                  # provision + FancyZones
Test-Clean.ps1                 # PII/secret scanner, exits 1 on findings
config/
  dev-config.winget            # what actually runs - WSL removed
  dev-config.upstream.winget   # pristine upstream copy, for diffing on update
  m365.winget                  # OPT-IN: OneDrive + Microsoft 365 Apps (-m365)
powertoys/
  Import-FancyZones.ps1        # enables FancyZones, imports layouts, overrides snap
  fancyzones/                  # drop custom-layouts.json etc. here (see below)
dotfiles/
  Configure-Terminal.ps1       # bell sounds + paste warnings, one settings.json write
.sounds/                       # bell sound pack (tracked on purpose)
```

## What's different from upstream

**`~/git` is created first.** Every repo gets cloned under `~/git`, and it's the
default working directory. The `GitWorkspaceDir` resource runs ahead of
everything else so nothing downstream has to assume it exists. It's idempotent,
and errors out rather than clobbering if a *file* happens to sit at that path.

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
| `fancyzones_quickLayoutSwitch` | Enables the Win+Ctrl+Alt+`<n>` layout bindings |

Without `moveWindowsBasedOnPosition`, only Win+Left / Win+Right get overridden
and Win+Up / Win+Down keep native Windows behavior.

Without `quickLayoutSwitch`, `layout-hotkeys.json` imports but the bindings never
fire. Current bindings:

| Hotkey | Layout |
| --- | --- |
| Win+Ctrl+Alt+0 | Priority Grid (1) |
| Win+Ctrl+Alt+1 | Big 4 and Middle |
| Win+Ctrl+Alt+4 | Big 4 |

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

## No Microsoft Store

Every package resource pins `source: winget`. Nothing installs from msstore.

MSIX is an installer *format*, not a source — `Microsoft.PowerShell` on ARM64
ships as MSIX and lands in `WindowsApps`, but it still comes from the winget
source. `winget list --source msstore` returns nothing.

The one exception is `winget configure --enable`, which internally resolves an
App Installer self-update through msstore (`ProductId: 9NBLGGH4NNS1`) and stalls
until it lands. `bootstrap.ps1` pre-empts that with an explicit
`winget upgrade --id Microsoft.AppInstaller --source winget` first.

To rule the Store out entirely:

```powershell
winget source remove msstore     # elevated; reversible with: winget source reset
```

Nothing in this repo needs it.

## Known: PowerShellScript units need a second pass

`Microsoft.DSC.Transitional/PowerShellScript` is declared with
`condition: "[not(equals(tryWhich('pwsh'), null()))]"` and executes via `pwsh`.
On a bare machine PowerShell 7 does not exist yet, so every unit of that type
reports **"Resource not found"** — `darkTheme`, the Cascadia font units,
`ps7default`, the Copilot profile, the WinUI templates, and `OhMyPosh/Shell`.

Since this config *installs* PowerShell 7, `bootstrap.ps1` detects that `pwsh`
appeared during the run and automatically re-applies the config so those units
resolve. Package and registry resources are unaffected — they have no such
condition and land on the first pass.

`GitWorkspaceDir` uses `WindowsPowerShellScript` (5.1, no condition) instead, so
`~/git` is created on a bare machine. `bootstrap.ps1` also creates it directly,
independent of DSC.

## Windows Terminal

`dotfiles\Configure-Terminal.ps1` owns every `settings.json` edit, applied as one
read-modify-write with a single backup.

### Paste warnings

Both of Terminal's paste confirmation dialogs are turned off. They're root-level
globals, not per-profile:

| Setting | Default | Set to | Dialog |
| --- | --- | --- | --- |
| `largePasteWarning` | `true` | `false` | Pasting more than 5 KiB |
| `multiLinePasteWarning` | `true` | `false` | Pasting anything containing a newline |

`multiLinePasteWarning` guards against pasting multi-line text that the shell
executes on arrival. Keep it with:

```powershell
.\dotfiles\Configure-Terminal.ps1 -SoundsSource .\.sounds -MultiLinePasteWarning $true
```

### Bell sounds

`.sounds/` is deployed to `~/.sounds` and wired into Windows Terminal's
**Defaults | Advanced | Bell sound**. Terminal's `bellSound` accepts an array and
picks one at random per bell, so the whole pack becomes the bell.

Deployed to the home folder rather than referenced in place — a path into the
repo clone breaks the moment the clone moves or is deleted.

The pack ships most sounds as both `.mp3` and `.wav`. Listing both would weight
those sounds double in the random pool, so the array is deduplicated by base
name, preferring `.wav` (override with `-PreferFormat`). 31 files currently
collapse to 16 unique sounds.

```powershell
.\dotfiles\Configure-Terminal.ps1 -SoundsSource .\.sounds -WhatIf   # dry run
.\dotfiles\Configure-Terminal.ps1 -SoundsSource .\.sounds
```

`bellStyle` is left alone — it defaults to `"audible"`, which plays the sound.
The script warns if it's set to something that would suppress audio.

Two caveats: `settings.json` is JSONC, and rewriting it **does not preserve
comments** (a `.bak` is written first). And if Terminal has never been launched,
the script seeds `settings.json` in `LocalState` rather than failing.

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
