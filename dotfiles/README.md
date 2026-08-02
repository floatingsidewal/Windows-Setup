# dotfiles

**This repo is public.** Dotfiles are the most common leak vector here, because
the useful ones carry identity by design. Commit sanitized `*.template` files
and let `bootstrap.ps1` fill in the real values.

Known offenders:

| File | Carries |
| --- | --- |
| `.gitconfig` | `user.email`, `user.name`, sometimes credential helper tokens |
| Windows Terminal `settings.json` | `startingDirectory` paths under `C:\Users\<name>` |
| VS Code `settings.json` | absolute paths, occasionally extension API keys |
| PowerShell `$PROFILE` | whatever you exported into it — check for API keys |
| `.ssh/config` | internal hostnames, jump hosts, usernames |

Pattern to use instead:

```
dotfiles/gitconfig.template     # committed, has {{EMAIL}} placeholder
dotfiles/gitconfig              # gitignored, generated locally
```

Run `..\Test-Clean.ps1` before pushing.
