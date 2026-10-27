# Contributing

This project targets 64-bit Windows PowerShell 5.1 with Windows Forms. Preserve
the native deployment model: no downloaded runtime dependencies, no execution
policy changes, and no stored credentials.

## Development and validation

1. Make a focused change and update documentation when behavior changes.
2. Run `Run-Tests.cmd` on Windows for core and mocked remote-decision checks.
3. Run `Test-Interface.ps1` in a fresh Windows PowerShell 5.1 STA process for GUI
   changes. This exercises synthetic workers and writes a local UI-Test folder.
4. Review changes for credential exposure, unsafe CSV handling, lost verification
   state, and any path that could issue an incorrect PASS.
5. Describe what was actually tested, including any live validation limitations.

Some development machines restrict unsigned scripts. Follow organizational policy;
the launchers deliberately do not bypass execution policy.

## Operational boundaries

The only authorized remote state change is the client software-update scan request.
Do not add update installation, restart, service control, policy reset, cache removal,
or repair actions without an explicit design and requirements review.

Never treat missing or unreadable evidence as a clean result. Preserve exact scan
request timestamps and boot identities across CSV round trips. Later waves must
operate on unfinished computers and must not reassess finished computers implicitly.

## Reports and examples

Use fictional computer names and synthetic results. Do not commit inventories,
operational CSVs, saved campaign settings, credentials, or diagnostic dumps from
real endpoints. Review `git diff --cached` before committing. The ignore rules
reduce accidental inclusion but do not replace review.

## Distribution

Release ZIPs belong in GitHub Releases rather than source history. Include the
matching SHA-256 checksum and state the validated runtime and test boundaries.
Keep packaged source consistent with its release tag when producing a new build.
