# Build 1.0.6 - 2026-10-27

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

- 50 core assertions: scan baselines, boot/catalog changes, malformed/missing evidence,
  formula escaping, CSV round trips, PASS accumulation/removal, header-only output,
  snapshots, duplicate/IP rejection, and exclusive file locks.
  Includes requested timestamp format, UTC conversion, exact-value round trips,
  display/tracking mismatch rejection, and legacy report compatibility.
  Includes prior-scope migration and accepted/rejected/unconfirmed acknowledgement shapes.
- 69 remote-decision assertions with mocked SCCM data: visible update blocking,
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
- All seven PowerShell files parsed successfully. The actual rendered GUI was visually
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
