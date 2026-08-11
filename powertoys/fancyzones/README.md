# FancyZones layouts

Drop these here, copied from the source machine's
`%LOCALAPPDATA%\Microsoft\PowerToys\FancyZones`:

- `custom-layouts.json`
- `layout-hotkeys.json`
- `layout-templates.json`
- `default-layouts.json`

`applied-layouts.json` and `app-zone-history.json` are deliberately gitignored —
they key off monitor hardware IDs and won't transfer.

`default-layouts.json` is the exception that does transfer: it keys off
`monitor-configuration` (`horizontal` / `vertical`), not hardware, so it decides
what a display FancyZones has never seen gets on first sight. Horizontal is set
to the custom Big 4 layout, vertical to the built-in rows/3. Without it every
fresh install ends at the editor (Win+Shift+`) assigning a layout by hand.
