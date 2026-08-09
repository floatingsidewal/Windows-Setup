# Windows-Setup

Repeatable provisioning for a Windows 11 dev box, on a Parallels guest or on
real hardware.

Wraps [microsoft/WindowsDeveloperConfig](https://github.com/microsoft/WindowsDeveloperConfig),
plus FancyZones layout import. The machine is detected at run time and one of
two modes applies — see [Modes](#modes).

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

   On a **Native** machine it then applies the native overlay and reboots to
   activate Virtual Machine Platform, resuming itself after you log back in to
   install Ubuntu and Docker Desktop. Pass `-NoReboot` to stay put. See
   [Modes](#modes).

3. **Assign a layout** — <kbd>Win</kbd>+<kbd>Shift</kbd>+<kbd>`</kbd> opens the
   editor. Pick an imported layout for the display, then verify:

   - Win+Left / Right / Up / Down move between zones
   - Win+Ctrl+Alt+0 / 1 / 3 / 4 apply the four layouts
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

### Optional: dark theme

Dark mode is **not** forced by default — it used to be, unconditionally, as part
of the base config. Opt in with `-DarkTheme`:

```powershell
cd ~/git/Windows-Setup
.\bootstrap.ps1 -DarkTheme
```

It lives in `config/theme.winget` and can be applied standalone:

```powershell
winget configure -f config\theme.winget --accept-configuration-agreements --disable-interactivity
```

### Already cloned

```powershell
cd ~/git/Windows-Setup
.\bootstrap.ps1 -DetectOnly # report the detected mode, change nothing
.\bootstrap.ps1 -WhatIf     # dry run
.\bootstrap.ps1             # needs elevation
```

Re-running `install.ps1` on an existing clone does a `git pull --ff-only`, so
local commits are never silently discarded.

## Modes

The machine is detected at run time by `lib\Get-MachineProfile.ps1` and one of
two modes applies.

| Mode | When | What it adds |
| --- | --- | --- |
| **Parallels** | SMBIOS or the `prl_*` services say this is a Parallels guest | Nothing — `config\dev-config.winget` only |
| **Native** | Anything else: bare metal, or a VM on another hypervisor | `config\native.winget` + `config\native-post.winget` on top |

Check what this box reads as without changing anything:

```powershell
.\bootstrap.ps1 -DetectOnly
```

Override the detection either way:

```powershell
.\bootstrap.ps1 -Mode Native      # force the full stack
.\bootstrap.ps1 -Mode Parallels   # force the lean profile
```

### What Native adds

- **WSL 2 + Ubuntu** — the three upstream phases this repo used to delete
- **Docker Desktop** — WSL2 backend, so it depends on the distro existing
- **Hyper-V, Containers, Windows Sandbox** — Pro/Enterprise/Education only
- **Sysinternals**

Detection also degrades on its own: a Home edition skips Hyper-V and Sandbox
rather than failing, and a machine with no visible virtualization extensions
gets a warning before anything is attempted.

### The reboot

Virtual Machine Platform is not active until the machine restarts, and nothing
WSL-hosted can install before it is. So a first Native run reboots — with a
20-second countdown you can Ctrl+C — registers a `RunOnce` key, and resumes
itself after you log back in (one UAC prompt). The resume applies
`native-post.winget`, which installs Ubuntu and Docker Desktop.

To stay put instead:

```powershell
.\bootstrap.ps1 -NoReboot     # install WSL components, do not restart
# ...reboot when convenient, then:
.\bootstrap.ps1 -Resume       # finish: Ubuntu + Docker Desktop
```

Upstream puts its reboot in the *middle* of the DSC apply, via a `RebootForVmp`
resource that calls `Restart-Computer -Force` from inside a `setScript` and then
throws so DSC marks the run failed. This repo keeps the auto-reboot and the
`RunOnce` resume but moves both into `bootstrap.ps1`, ordered **after** the base
config, Terminal and FancyZones. Rebooting mid-apply means an interrupted resume
costs the entire provision; rebooting at the end costs only the WSL/Docker half.

### WSL does not need Hyper-V

A common mix-up worth stating plainly: **WSL 2 requires
`VirtualMachinePlatform`, not Hyper-V.** VMP registers the same `vmcompute`
(Host Compute Service) plumbing WSL 2 runs on, without the Hyper-V role, the
virtual switch stack, or Hyper-V Manager. Hyper-V is enabled in Native mode
because a real machine is the one place it is useful, not because WSL needs it —
drop `Microsoft-Hyper-V-All` from `config\native.winget` and WSL and Docker are
unaffected.

Note also that `Microsoft-Hyper-V` and `Microsoft-Hyper-V-All` are different
features, and that the `-All` switch on `Enable-WindowsOptionalFeature` enables a
feature's **parents**, not its children:

| Command | Result |
| --- | --- |
| `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All` | Hypervisor and services, **no** Manager GUI or PowerShell module |
| `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All` | Hypervisor **plus** Hyper-V Manager and the PowerShell module |

`config\native.winget` uses the second.

## Layout

```
install.ps1                    # irm | iex entry point: git -> clone -> elevate
bootstrap.ps1                  # detect mode -> provision -> FancyZones -> native extras
Test-Clean.ps1                 # PII/secret scanner, exits 1 on findings
lib/
  Get-MachineProfile.ps1       # Parallels vs Native detection (-DetectOnly)
config/
  dev-config.winget            # base, both modes - WSL removed
  dev-config.upstream.winget   # pristine upstream copy, for diffing on update
  native.winget                # NATIVE: virtualization features + WSL components
  native-post.winget           # NATIVE, post-reboot: Ubuntu distro + Docker Desktop
  theme.winget                 # OPT-IN: force dark mode (-DarkTheme)
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

**WSL Phases 1-3 are removed from the base config.** A Parallels guest has no
nested virt, and upstream's Phase 2 (`RebootForVmp`) calls `Restart-Computer
-Force` mid-run. Nothing else in the file had a `dependsOn` pointing at the WSL
resources, so it cut cleanly (962 → 909 lines). They are **not** gone from the
repo — they were rebuilt into `config/native.winget` and
`config/native-post.winget`, which Native mode applies. See
[Modes](#modes).

**Dark theme is opt-in.** Upstream's `darkTheme` unit ran on every provision and
forced dark mode with no way to decline. It now lives in `config/theme.winget`
and only applies with `-DarkTheme`.

**Edge searches Google, not Bing.** Four `DefaultSearchProvider*` policy values
under `HKLM\SOFTWARE\Policies\Microsoft\Edge`. There is no user-preference
registry value for this — Edge keeps the chosen engine in the profile's Web Data
database — so policy is the only declarative route. The trade-off: a
policy-set provider is *enforced*, so `edge://settings/searchEngines` shows it as
managed and the dropdown is locked. Delete the four `EdgeSearchProvider*`
resources to hand the choice back to the UI.

**Claude and Copilot are installed.** `Anthropic.ClaudeCode`,
`Anthropic.Claude`, and both halves of GitHub Copilot — `GitHub.Copilot` (the
CLI, which `AddWinSkillsMarketplace` and `InstallWinUIPlugin` drive) and
`GitHub.CopilotApp` (the desktop app). They are separate packages; installing
the CLI does not give you the app.

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

| Hotkey | Layout | Shape |
| --- | --- | --- |
| Win+Ctrl+Alt+0 | Priority Grid (1) | 3 columns, 25 / 50 / 25 |
| Win+Ctrl+Alt+1 | Big 4 and Middle | canvas: 4 columns plus a wide middle zone |
| Win+Ctrl+Alt+3 | Big 3 | 3 equal columns |
| Win+Ctrl+Alt+4 | Big 4 | 4 equal columns |

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
