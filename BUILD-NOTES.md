# Patch Checkpoint 1.0.0 - 2026-10-28

## Changes from 0.9.0-beta.6

- Owner authorized the 1.0 transition. Application and executable versions are 1.0.0.
- Collected functional sources, launchers, examples, tests and build code under app/;
  documentation remains outside that folder for a cleaner GitHub landing page.
- Added a native x64 C# WinForms host using Windows PowerShell 5.1 on its STA thread.
  Application and help resources are embedded, so loose script files are not required
  beside the distributed EXE. No installer or downloaded runtime is introduced.
- Embedded resources are materialized in an owner/SYSTEM-only temporary directory
  for the remote assessment file and diagnostic hashes. Normal exit deletes only
  known files. Session settings are kept separately under LocalAppData\PatchCheckpoint.
- Added source build and synthetic executable self-test workflows. Script mode
  retains ordinary file loading; EXE mode executes its trusted embedded resources.
- Existing CSV schema, campaign JSON and SCCM assessment decisions are retained.

1.0.0 validation: 113 core/export assertions and 92 mocked remote assertions passed
under Windows PowerShell 5.1. The relocated source application's complete synthetic
GUI suite passed. The exact release EXE passed its isolated synthetic test for private
runtime ACLs, WinRM command availability (without connecting), embedded help, STA UI,
bounded workers, automatic verification, Excel/diagnostic exports, campaign restore,
and activity layout. Normal exit removed its temporary resources. An existing
self-test output file was preserved on rejection. PE headers identify an x64 Windows
GUI executable; product/file version is 1.0.0.0. Authenticode status is NotSigned.

Live WinRM/SCCM operations, organization endpoint-security policies, SmartScreen
reputation and behavior on other Windows installations have not been validated for
the EXE. The version transition is owner-authorized, not a claim of those tests.


## Changes from 0.9.0-beta.5

- Reparented the existing message label into a right-side activity card so every
  existing status assignment, including diagnostic/export errors and countdowns,
  uses the same presentation. No assessment or scheduling logic changed.
- Added a dynamic countdown heading, red error accents, wrapped text and a scroll
  container to preserve long messages. Kept the original text for diagnostic capture.
- Reserved space on the right, retained two-column scrolling worker slots on the
  left, allowed status badges to wrap, and reclaimed the bottom footer margin.
- GUI regression checks cover countdown/error styling, long text, minimum-window
  containment, worker separation, existing view toggles and the complete workflow.


## Changes from 0.9.0-beta.4

- Added Diagnostics.Export.ps1: explicit data-only UI snapshot and background ZIP
  creation. No server queries or scans are dispatched by this path. Saved CSVs and
  .bak attachments are selected individually, not by recursive folder enumeration.
- Captured full campaign rows, scan evidence, state counters, worker/staged summaries,
  local runtime, source hashes and a bounded 2,000-entry application event history.
  Credentials never enter the snapshot or background worker arguments.
- Missing/unreadable/oversized attachments are listed in the manifest; source code,
  raw inventory/session files, process memory and environment dumps are excluded.
- Diagnostic failures release their worker independently of assessment/report state.
  A staged ZIP replaces the destination only after collection completes; failed
  exports preserve existing archives. Close waits for a diagnostic export to finish.
- Promoted campaign outcome totals to a persistent 14-point heading above progress.
  Attention means ACTION REQUIRED, NOT READY or UNABLE TO DETERMINE, not queued/running.
- Existing report schemas, SCCM decisions and wave selection remain unchanged.

Beta.5 validation: 113 core/export assertions and 92 mocked remote assertions passed
under Windows PowerShell 5.1. Actual GUI tests passed for active-wave exports,
credential canary exclusion, full campaign capture, export after a report failure,
destination errors, existing wave/recovery flows, and the prominent outcome totals.
All nine scripts parsed. The synthetic screenshot was inspected. This diagnostic
collector has not been exercised against the new live issue yet.

## Changes from 0.9.0-beta.3

- Rebranded the title, dialogs, About, script descriptions, launcher, repository
  links, package names, and new-campaign Documents folder to Patch Checkpoint.
- Renamed the main script to Start-PatchCheckpoint.ps1 and updated the GUI harness.
- Separated a concise README landing page from the complete USER-GUIDE.md, which
  remains available in the application's Help menu. Disclosed AI assistance in both
  the README and About; included an actual synthetic application screenshot.
- Kept Validation-Session.json as the local resume-pointer filename for compatibility;
  existing campaign paths are restored as saved, without moving or renaming user data.
- This build changes branding and documentation, not remote assessment decisions.

Beta.4 validation: 97 core assertions and 92 mocked remote assertions passed under
Windows PowerShell 5.1. The actual synthetic GUI suite passed with the renamed
entry script, branded title and About disclosure, separate User Guide, campaign
restore, reporting, and cancellation. All eight scripts parsed; local documentation
links and the published synthetic screenshot were checked. Live endpoint and desktop
Excel validation remain outside this build's automated checks.

## Changes from 0.9.0-beta.2

- Added a Campaign folder input with FolderBrowserDialog. A pre-start folder
  change updates both report filenames without touching disk; first startup creates
  the selected folder. The resume file is placed alongside the unfinished report.
- Folder selection is restored from saved report paths without changing legacy
  split-output campaigns. It locks with other campaign paths after starting.
- Export Report defaults to the selected folder, while retaining explicit Save As.
- New campaigns refuse an occupied campaign destination before writing or dispatch.
- Synthetic GUI regression coverage includes custom folder paths with spaces,
  creation timing, resume-file placement, path restoration, locking, and collision
  rejection. No endpoint query logic or credential handling changed.

## Changes from 0.9.0-beta.1

- Removed the banner; retained the application name/version in the native title bar.
- Added Export Report with six-column CSV view export and full-campaign Excel
  export, with seven status tabs. XLSX uses inline text and built-in .NET ZIP/XML;
  no Excel/COM dependency, formulas, macros, or external links are generated.
- Generated unique campaign destinations under Documents when the inventory loads;
  create working CSVs and Campaign.json on first start. Keep session version 1 and
  schema 4 compatibility, optional path overrides, and local last-campaign restore.
- Added a single timer-driven verification follow-up 60 seconds after a successful
  initial pass is checkpointed. No blocking sleep, recurring retry, or automatic
  scan resubmission. Stop cancels the wait, preserving checkpointed state.
- Accepted ComputerName/SERVERNAME CSV headers and skipped repeated/blank headers.

Validation for beta.2: 97 core assertions and 92 mocked remote assertions passed
under Windows PowerShell 5.1. The actual GUI harness passed inventory-only defaults,
automatic verification, portable resume-file creation, cancellation during the scan
window, status-tab export independent of filtering, and existing responsiveness,
checkpoint, remediation and recovery scenarios. All eight scripts parsed. Workbook
package XML and tab contents were inspected; opening it in desktop Excel and live
SCCM testing are not yet validated for this revision.


## Changes from test build 1.0.8

- Returned application versioning to pre-1.0 beta at the owner's direction.
- Restricted visible updates to Windows OS/.NET patches through explicit title
  rules; excluded known other products and made ambiguous titles require review.
- Removed all PFRO/PFRO2 reads and the generic SCCM reboot query. Only scoped update
  reboot states, CBS, and Windows Update registry indicators control reboot findings.
- Added scoped failure fields based on EvaluationState 13, with error details
  and Yes/No/Unknown failure notes for NOT READY results.
- Made status totals clickable filters; added contextual tooltips.
- Split collapsible Wave setup from the always-available Checks pane.
- Added View-toggleable worker progress slots using actual pipeline progress records,
  with honest waiting, per-computer stage text, and elapsed time.
- Corrected overall percentage to use selected wave work rather than all campaign rows.
- Retained schema 4 and session version 1, with additive report fields and optional
  saved UI preferences. Legacy scope labels require reassessment rather than relabeling.

## Changes from 1.0.7

- Added File, Actions, View, and Help menus, keyboard shortcuts, row-copy context
  menu, local help windows, report-folder shortcuts, and version/runtime About.
- Added UI.Commands.ps1 and TROUBLESHOOTING.md using built-in Windows Forms only.
- Primary follow-up checks only VERIFICATION PENDING computers. Reassess unfinished
  explicitly checks every remaining computer after remediation. PASS stays finished.
- Work indices are separate from the full campaign data. Skipped results remain in
  the GUI and CSV unchanged, including their reasons, timestamps, and scan tracking.
- No pending verification reports an attention count rather than declaring the
  campaign complete. Progress counts only work selected for that wave.
- Resume campaign validates all settings and reports before switching, and saves
  local paths without credentials. Header-only report readers dispose their streams.
- Extended offline and GUI tests for wave selection, skipped CSV records, menus,
  shortcuts, help, view toggles, resume validation, and explicit remediation flow.

## Changes from 1.0.6

- Added Export CSV for the filtered/searched/sorted Computer status table only.
  Export captures a point-in-time snapshot and writes it in the background, with
  spreadsheet formula escaping and protection against overwriting campaign files.
- Made Unfinished the default filter.
- Moved tracking CSV conversion and writes to one background runspace. Batched
  dispatch intents must be saved before remote work starts. Snapshot data is copied;
  background writers never access GUI controls or live mutable row collections.
- Limited result processing/worker launches per timer tick, throttled summaries,
  counted statuses in one pass, and suppressed bulk binding notifications.
- A completed wave waits for the final checkpoint. Stopping during a checkpoint
  cancels undispatched work. Background report failures stop dispatch, drain active
  work, expose the error, and prevent unsafe continuation until recovery.
- Extended tests for display export, default filtering, GUI heartbeat while saves
  are deliberately delayed, checkpoint dispatch barriers, stopped staged work,
  a 500-computer synthetic checkpoint, and a failing background report writer.

## Changes from 1.0.5

- Loads the original input only for the first wave. Run next wave automatically
  reloads the unfinished CSV, preserving verification requests without path edits.
- Locks campaign paths after startup; New list unlocks setup and resets local
  session settings without deleting reports. Credentials/concurrency remain usable.
- Keeps finished computers viewable while excluding them from later worker queues.
- Saves paths/concurrency in Validation-Session.json, separately from Demo settings.
  Reopening restores the remaining queue and finished list; credentials are never
  persisted, and startup performs no remote actions. Invalid recovery fails closed.
- Handles header-only unfinished output as campaign completion, with no new workers.
- Extended actual GUI tests to leave the original input unchanged across waves,
  restore the campaign, exclude PASS computers, retain finished viewing, stop safely,
  reset the campaign without deleting reports, and avoid restarting completed work.

## Changes from 1.0.4

- Existing requests remain pending on boot/source mismatches. The tool no longer
  silently replaces the request timestamp and submits another scan in this case.
- Added VerificationContextJson to CSVs and computer details, recording the exact
  comparison inputs and decision for diagnosis across waves.
- Preserved prior request evidence when boot time changes during assessment.
- Normalized imported JSON arrays for source comparisons in Windows PowerShell
  5.1. Multiple sources no longer produce false mismatches from nested arrays.
  Actual version changes and missing history still prevent PASS.
- Reproduced the pilot timestamp/CSV shape: the recorded 14:16:30 scan cannot
  confirm the latest 14:17:12 request; qualifying later evidence can confirm it.
  The supplied row alone cannot prove why the earlier request was replaced.
- Existing unfinished reports remain usable; retain their tracking data.

## Changes from 1.0.3

- Restricted the operational authority to Software Center-visible updates, using
  CCM_SoftwareUpdate with UserUIExperience=True, and pending-reboot indicators.
- Hidden deployments no longer block update assessment. The broad update-store
  query and its informational CSV fields have been removed entirely.
- Visible count column is Updates; UpdateScope explicitly identifies visibility.
- Report schema 4 reads prior schemas, preserves request/timestamp tracking, and
  clears previous-scope counts until reassessment rather than changing their meaning.
- Missing/null/malformed scan ReturnValue now preserves an Unconfirmed request
  and yields VERIFICATION PENDING. It cannot authorize PASS or automatic resubmission.
- Explicit nonzero scan codes and thrown errors still fail. Assessment error
  diagnostics explicitly record stage and exception information.
- Existing saved request boundaries from the reported 1.0.3 failure can be reused
  in the next wave without submitting another scan.

## Changes from 1.0.2

- Corrected operational scope: CCM_SoftwareUpdate deployed/applicable outstanding
  updates now control ACTION REQUIRED and PASS. Hidden deployments also count.
- Broader CCM_UpdateStatus missing records are informational, with separate count,
  details, and query-status fields. They neither block verification nor force action.
- Renamed the visible count column to Deployed. Details include deployment visibility.
- Upgrades old broad-store report counts into informational fields instead of labeling
  them as deployments. Report schema is now 3, with schemas 1-2 accepted as input.
- Confirmed the reported case with synthetic evidence: 12 broad-store records and
  zero deployments produces VERIFICATION PENDING, then PASS after qualifying evidence.
- Preserves the approved visual style, timestamps, report persistence, and scan workflow.

## Changes from 1.0.1

- Applied the approved light visual style to the working interface: rounded cards,
  navy typography, blue action/progress, colored status pills, and a softer results
  table and details area.
- Grouped setup, progress/summary, and computer results into resizable cards.
- Added UI.Theme.ps1 with built-in Windows Forms/GDI+ drawing; no external packages.
- Removed the internal schema number from the selected computer's display details.
- Retained assessment logic, CSV tracking, no-prompt updates, and timestamp behavior.
- Validated themed controls and layout at the minimum window size, as well as the
  existing actual GUI/runspace two-wave and graceful-stop checks.

## Changes from 1.0.0

- Removed the existing-report update confirmation. Starting a wave saves into the
  selected CSVs automatically, retaining the latest-state reporting model.
- Changed grid, detail-pane, and top-level CSV timestamps to MMDDYYYY HH:MM:SS.
  UTC remains the clock reference.
- Added schema 2 timestamp metadata so presentation rounding does not change exact
  boot/scan verification. Reads schema 1 reports from 1.0.0 for upgrade continuity.
- Confirmed that the actual GUI can start the next wave using the same input/output
  report paths without a modal prompt, while retaining tracking and PASS results.

Fresh implementation following the revised wave-based requirements. This package
does not include the earlier deleted prototype.

## Delivered behavior

- One GUI for CSV paths, credentials, concurrency (default 8), live scrollable status,
  filtering/searching, details, and graceful stop.
- One assessment attempt per computer per wave; no recovery/retry wait loop.
- Software Center-visible update assessment; no hidden/broad-store update inventory.
- Windows/SCCM readiness and pending-reboot checks with evidence-based reasons.
- Scan request only after preliminary clear checks; VERIFICATION PENDING until a
  later wave establishes new valid completion evidence.
- PASS accumulation and reusable unfinished CSV with verification state.
- Checkpoints, per-file atomic replacement, .bak snapshots, exclusive report locks,
  and conservative handling of interrupted scan submission.
- Synthetic offline demo that rejects its tracking state in live assessments.

## Validation performed

Executed under Windows PowerShell 5.1 on Windows:

- 80 core assertions: scan baselines, boot/catalog changes, malformed/missing evidence,
  formula escaping, CSV round trips, PASS accumulation/removal, header-only output,
  snapshots, duplicate/IP rejection, and exclusive file locks.
  Includes requested timestamp format, UTC conversion, exact-value round trips,
  display/tracking mismatch rejection, and legacy report compatibility.
  Includes prior-scope migration and accepted/rejected/unconfirmed acknowledgement shapes.
- 92 remote-decision assertions with mocked SCCM data: visible update blocking,
  hidden update exclusion, no broad-store query, independent reboot flags, readiness,
  required query failures, inconsistent snapshot, rejected/thrown scan submissions,
  and interrupted dispatch. Empty, absent, null and malformed acknowledgement cases
  each check that no duplicate scan is submitted, no old evidence can PASS, and a
  newer valid completion can subsequently PASS.
- Actual WinForms/runspace demo: first wave; second wave producing four PASS and
  eight unfinished computers; graceful stop completing two active workers while
  preserving ten queued computers. Maximum concurrency was checked at two.
  Second wave reused the same existing output files without an update prompt;
  both exported and displayed timestamp formats were checked.
  Visible-update column labeling and removal of broader-store fields were checked.
- All eight PowerShell files parsed successfully. The actual rendered GUI was visually
  inspected; GUI-preview.png is a synthetic run of this build, not the concept image.
- Packaged file hashes and archive contents were checked during release packaging.

## Not yet validated

This revision was not executed against production endpoints, real credentials, live
scan submission, physical reboots or servicing. Earlier user pilot results informed
the scope correction; scan-history compatibility still needs live validation.
The local tests exercised trusted sources in memory because of execution
restrictions in the development environment; the production launcher uses normal
-File execution and does not change or bypass execution policy.

Begin with a small representative live pilot. If a class/property differs on your
client version, the tool should report UNABLE TO DETERMINE and retain diagnostics
rather than issue PASS. Review the record in the detail pane and exported CSV.

The readiness definition in this build is an explicit two-minute startup guard,
running CcmExec, accessible required data, and no SCCM update installing/verifying.
It is not an application or complete Windows servicing health determination.
