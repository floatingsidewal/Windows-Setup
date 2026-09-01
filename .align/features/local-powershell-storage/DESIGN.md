# Design: Local PowerShell Storage

## Context

PowerShell derives profile and current-user module locations from the Windows
Documents known folder. Enterprise redirection can place that folder in
OneDrive even when PowerShell state should remain local.

## Architecture

A focused `dotfiles\Configure-PowerShellStorage.ps1` script:

1. Resolves Documents and local application data at runtime.
2. Creates local physical directories for Windows PowerShell and PowerShell 7.
3. Copies existing content from Documents, then removes the original directory
   only after the copy succeeds.
4. Creates directory junctions at the standard Documents paths.
5. Removes the redirected module directories from `PSModulePath` and adds the
   local module directories.

`bootstrap.ps1` invokes the script after provisioning and optional package
configuration, so any profiles/modules created earlier in the run are migrated.

## Interfaces and Data Flow

- Default input: `%LOCALAPPDATA%` and the `MyDocuments` known folder.
- Test input: explicit local application data and Documents paths.
- Persistent output: two local directories, two junctions, and the current
  user's `PSModulePath`.

## Decisions

- **LPS-1:** Use directory junctions so existing PowerShell path conventions
  continue to work without profile-specific overrides.
- **LPS-2:** A reparse point with an unexpected target is an error; setup does
  not replace links it cannot prove it owns.
- **LPS-3:** Check for conflicting destination content, copy before removal,
  and use terminating errors. Failed migrations leave the source directory
  intact and never overwrite a different local file.
- **LPS-4:** Preserve existing non-redirected module paths and standard machine
  paths while removing only the two redirected module directories.

## Failure Behavior

- Missing runtime path inputs, conflicting files, incorrect junction targets,
  copy failures, removal failures, and junction creation failures stop setup
  with a terminating error.
- No copy error is suppressed.

## Security and Privacy

All paths are resolved from the current user's environment or known folders.
No user identity, company path, or machine identifier is stored in the repo.

## Verification Strategy

- Parse all PowerShell scripts with the PowerShell parser.
- Run the configuration script against isolated temporary directories using a
  process-scoped module path.
- Verify migration, junction targets, idempotence, and bootstrap integration.
- Run `Test-Clean.ps1` before publishing.

## Open Questions

None.
