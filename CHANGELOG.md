# Changelog

## 1.0.0 - 2026-10-28

- First owner-authorized 1.0 release; earlier 1.0.x tags remain historical test builds.
- Moved runnable PowerShell files, launchers, examples, tests and build sources into
  app/. Kept README, help, security and project documentation at the repository root.
- Added PatchCheckpoint.exe: a native x64 Windows host with embedded application/help
  resources, Windows PowerShell 5.1 STA runtime, and no third-party runtime downloads.
- EXE resources use a new private runtime directory per process and normal-exit cleanup.
  Per-user session settings persist under LocalAppData, outside the temporary code folder.
- Added EXE build sources and an explicit synthetic self-test covering GUI, worker
  concurrency, verification, Excel/diagnostic exports, embedded help and campaign resume.
- Retained the PowerShell source distribution and existing campaign/report schemas.
  The EXE and scripts remain unsigned; live EXE/endpoint-security pilot testing is required.

## 0.9.0-beta.6 - 2026-10-28

- Moved bottom-of-window progress, countdown, error and export messages into a
  rounded Current activity card on the right of the progress section.
- Added a Next check in ... countdown heading, red error accents, wrapped messages
  and scrolling for long notices. The card remains visible when worker bars are hidden.
- Rebalanced progress/worker layout and reclaimed the former footer space for results.
- Preserved message text, diagnostic capture and all assessment/countdown behavior.

## 0.9.0-beta.5 - 2026-10-28

- Added Help > Diagnostic Export for background, local-only support ZIPs with
  full in-memory campaign/verification evidence, saved report CSVs/backups, runtime
  settings, worker stages, recent application events, source hashes and a manifest.
- Excluded credential objects, environment/memory dumps, raw session JSON, source
  contents, original inventory contents and unrelated files. Bundles contain
  infrastructure details and must be reviewed before sharing.
- Added a persistent, larger campaign overview above the main progress bar showing
  finished, verification-pending and attention totals independently of footer messages.
- Tested active-wave exports, credential canary exclusion, report-failure recovery,
  missing attachments, archive hashes, destination errors and safe failed replacements.

## 0.9.0-beta.4 - 2026-10-28

- Renamed the application and repository to Patch Checkpoint. The entry script is
  Start-PatchCheckpoint.ps1; Launch.cmd and the application repository link follow the new name.
- Reworked the README as a concise landing page with a real synthetic screenshot,
  quick start, status guide, and explicit AI-development disclosure.
- Preserved the detailed instructions in USER-GUIDE.md and linked the in-app Help
  menu to it. Added the AI disclosure to About as well.
- Renamed distribution ZIPs and the default Documents folder for new campaigns.
  Existing campaign/report formats and Validation-Session.json remain compatible.

## 0.9.0-beta.3 - 2026-10-28

- Added an editable Campaign folder field and native folder picker. Selecting a
  folder places Finished.csv, Unfinished.csv, and Campaign.json directly there.
- Retained the folder across waves and restarts, locking it once work begins.
  Export Report defaults to the campaign folder; existing split-path sessions remain readable.
- Prevented new campaigns from silently reusing a folder containing campaign files.
- Tested folder selection, creation, restore, locking, and existing-file protection
  through the actual synthetic GUI workflow.

## 0.9.0-beta.2 - 2026-10-28

- Removed the redundant content banner and reclaimed its space for results.
- Renamed Export CSV to Export Report. Added dependency-free .xlsx export of all
  campaign results on status-category tabs; CSV retains the selected table view.
- New inventories receive unique campaign folders under Documents with generated
  finished/unfinished CSV paths and Campaign.json resume settings. Existing sessions
  remain compatible and the local last-campaign pointer still restores on startup.
- Initial assessments automatically check pending verification once after a
  nonblocking 60-second scan window. Stop cancels the follow-up. Existing evidence
  requirements remain unchanged; slow scans may still need another manual wave.
- Accepted SERVERNAME as well as ComputerName headers; skipped blank and repeated
  header rows so column names are never assessed as targets.
- Added regression coverage for Excel packages, input headers, automatic follow-up,
  campaign defaults, and cancellation. Endpoint behavior still needs a live pilot.

## 0.9.0-beta.1 - 2026-10-27

- Pre-1.0 beta versioning; earlier 1.0.x builds remain historical test artifacts.
- Windows OS/.NET-only visible patch scope, with ambiguous titles requiring review.
- Strict OS reboot signals; PFRO/PFRO2 and generic SCCM reboot flags are ignored.
- Failure details and Yes/No/Unknown failure notes for NOT READY computers.
- Clickable status totals, contextual tooltips, separate Checks pane, collapsible setup.
- View-toggleable per-worker assessment stage bars and saved layout preferences.

## 1.0.8 - 2026-10-27

- Native File, Actions, View, and Help menus with familiar keyboard shortcuts.
- Verification-only follow-up and an explicit Reassess unfinished action.
- Skipped findings retain their full state in the GUI and tracking CSVs.
- Validated campaign resume, local help, runtime About, and report-folder commands.
- Row context menu copies computer name, status summary, or detailed results.
- Filter checkmarks, details-pane toggle, and reset-view command.

## 1.0.7 - 2026-10-27

- Export CSV captures the current filtered, searched, and sorted status table.
- Unfinished is the default computer-status filter.
- Background report writer and batched checkpoints reduce repeated UI-thread work.
- Dispatch still waits for durable intent; wave completion waits for the final save.
- Bounded UI processing, throttled summary refresh, and more efficient list loading.
- Extended GUI tests cover slow writes, 500-computer snapshots, and writer failures.

## 1.0.6 - 2026-10-27

- Automatic continuation from the unfinished report after the initial wave.
- Preserved scan tracking without manually changing the input path.
- Finished computers remain viewable and are excluded from later worker queues.
- Campaign path locking, explicit New list action, and restart recovery.
- Local session settings contain paths and concurrency, never credentials.
- Completed campaigns start no further workers.

## 1.0.5 - 2026-10-27

- Retained pending requests across boot/source mismatches, with comparison diagnostics.
- Corrected Windows PowerShell 5.1 JSON array handling for multiple update sources.

## 1.0.4 - 2026-10-27

- Scoped update decisions to Software Center-visible SCCM updates and pending reboot.
- Removed broader update-store inventory from operational decisions and reports.
- Treated missing scan acceptance codes as unconfirmed, requiring completion evidence.

## Earlier builds

See BUILD-NOTES.md for the development history and validation details.
