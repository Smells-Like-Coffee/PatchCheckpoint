# Changelog

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
