# Keyboard Manager remaps

macOS-compatible key remaps, copied from
`%LOCALAPPDATA%\Microsoft\PowerToys\Keyboard Manager`:

- `default.json` — what the remap engine reads.
- `editorSettings.json` — what the Keyboard Manager editor UI reads. Both are
  tracked on purpose: with only `default.json` the remaps fire, but the editor
  shows an empty list and wipes them the next time you save from it.

The point is that the Mac's Cmd key (which arrives in Windows as the Win key)
behaves like Cmd. Every mapping below displaces a Win shortcut that is either
unused on these machines or still reachable another way.

| Press | Sends | Displaces |
| --- | --- | --- |
| Caps Lock | Ctrl+Alt+Break | — (releases the Parallels/VM mouse grab) |
| Win+A / C / V / X | Ctrl+A / C / V / X | Quick Settings, Copilot |
| Win+W | Ctrl+W | widgets |
| Win+Q | Alt+F4 | search |
| Win+Z | Ctrl+Z | snap layouts flyout (FancyZones covers this) |
| Win+Shift+Z | Ctrl+Y (redo) | — |
| Win+S | Ctrl+S | search — Win on its own still searches |
| Win+F | Ctrl+F | Feedback Hub |
| Win+O | Ctrl+O | orientation lock |
| Win+N | Ctrl+N | notification centre |
| Win+T / Win+Shift+T | Ctrl+T / Ctrl+Shift+T | taskbar cycling |
| Win+B | Ctrl+B | notification-area focus |
| Win+U | Ctrl+U | Accessibility settings |

Win+I (Settings), Win+E (Explorer), Win+R (Run), Win+P (project display) and
Win+L (lock) are deliberately left alone.

Win+Z and Win+T are the only entries with `exactMatch: true` — without it they
would swallow their own Win+Shift+ variants.

## Refreshing the snapshot

Edit the remaps in the PowerToys UI (Win+Shift+Q), then copy both files back:

```powershell
Copy-Item "$env:LOCALAPPDATA\Microsoft\PowerToys\Keyboard Manager\default.json",
          "$env:LOCALAPPDATA\Microsoft\PowerToys\Keyboard Manager\editorSettings.json" `
          .\powertoys\keyboard-manager\ -Force
```

Keep `appSpecific` empty — app-specific remaps store absolute program paths and
would leak a username into the repo.
