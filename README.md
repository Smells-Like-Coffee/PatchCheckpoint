# Server Update Validation 0.9.0-beta.3

Windows desktop tool for post-monthly-reboot assessment using SCCM client data. Computers
are assumed to have SCCM installed, to have recently rebooted, and to respond to ping.
The initial assessment checks the input list, waits 60 seconds for SCCM scan work,
then automatically checks only pending verification once. Later actions separately
check pending verification or reassess unfinished computers after remediation.
There is no continuous retry loop, installation, or automatic reboot.

The operational scope is **Software Center-visible Windows OS and .NET patches,
with strict patching/OS reboot detection that ignores PFRO entirely**, followed by
verification of a qualifying SCCM client scan. It is not a
complete Windows update inventory or an application-health assessment.

Download the packaged ZIP and matching checksum from this repository's **Releases**
page, or clone the repository and keep the source files together. The current
version is **0.9.0-beta.3**. This is beta software; earlier 1.0.x tags were test-build
labels, not a general-availability declaration. Future builds remain below 1.0 until
the owner explicitly authorizes that transition. The owner has reported successful
live testing of earlier builds; compatibility
with other SCCM client versions and environments still requires validation.

Use the ZIP matching the version in the application title. Older downloads are
historical test artifacts.

## Start here

1. Extract the entire ZIP into a writable local folder on the administrative computer.
   Keep all supplied files together. Do not run directly inside the ZIP.
2. Optionally double-click **Demo.cmd** first. It uses synthetic results only, creates
   Demo-Finished.csv and Demo-Unfinished.csv, and needs no credentials or network access.
3. Double-click **Launch.cmd** for real assessments.
4. Select a CSV containing a **ComputerName** or **SERVERNAME** header, supply
   credentials, choose concurrency and your **Campaign folder**, then click
   **Start wave**. Report filenames are generated inside that folder. The initial run includes one verification follow-up
   after a 60-second scan window. Only VERIFICATION PENDING computers are checked
   again; pending scans that have not completed remain pending.
5. Click **Check pending verification** to follow up only VERIFICATION PENDING
   computers. ACTION REQUIRED, NOT READY, UNABLE TO DETERMINE, and queued computers
   retain their existing results, timestamps, and tracking without being reassessed.
6. Resolve reported issues on the affected servers, then click **Reassess unfinished**.
   This assesses every remaining computer, including pending verification. Newly
   clear computers may need another verification-only wave before they pass.
   The application loads its unfinished report automatically; no path changes are
   needed. PASS computers accumulate in the finished report and remain viewable.
7. After closing and reopening from the same extracted folder, the application
   restores the campaign paths and remaining list. Enter credentials again, then
   choose either follow-up action. Nothing runs automatically on startup.

The original input field stays visible and locks with the output paths after the
first wave starts. **New list** unlocks setup and clears saved session settings,
without deleting reports. Selecting the next input generates a fresh campaign
folder, keeping monthly runs separate. To continue an older
campaign that has no session settings, select its unfinished CSV as the initial
input and its existing report paths once. Input and unfinished output may be the
same file; finished must be a separate file.

## Campaign files: what the operator supplies

For a new campaign, supply the computer-name CSV and select the **Campaign folder**
by typing its path or clicking Browse. This is the exact folder where Finished.csv,
Unfinished.csv, and Campaign.json will be placed; no extra subfolder is appended.
The application proposes a unique destination under Documents as a starting point,
which you can replace. A nonexistent folder is created when the assessment starts.
The folder stays locked for the campaign, survives reopening, and is the default
destination in Export Report. You may choose a different location for an export.

Choose a separate campaign folder for each monthly run. If it already contains
campaign files, use **File > Resume campaign** to continue them, or select another
folder. The application will not silently mix a new campaign with those files.
Individual report paths remain available before starting for compatibility with
existing installations that stored their reports in separate folders.

The application creates **Finished.csv** (confirmed PASS results), **Unfinished.csv**
(all remaining findings and scan evidence), and **Campaign.json** (resume settings).
These are application working files, not files you need to prepare. Keep them
together and retain their tracking columns. Paths inside Campaign.json are absolute;
moving the folder requires updating those paths before resuming.

Reopening the same application folder restores the most recent campaign without
starting work. Use **File > Resume campaign** and select a campaign's Campaign.json
to reopen an older campaign. Credentials must be reentered. **New campaign/New list**
clears the current selection and creates a fresh destination for the next input;
previous campaign folders are preserved. Do not select an unfinished report to
start a new monthly campaign; use the original names-only inventory.

**Export Report** creates a separate review copy. It is optional and never replaces
the working CSVs or their verification evidence.

Starting another wave updates the selected CSVs automatically, without an existing-report
confirmation prompt. Finished PASS results accumulate and unfinished output contains
the current outstanding results. This is latest-state reporting, not a separate history
of every wave. Automatic .bak snapshots are still retained.

To update an existing installation, finish or gracefully stop the wave and close
the application. Replace the program files in the existing working folder with
the new distribution. Keep Validation-Session.json and your operational CSVs;
the report schema remains compatible. Relaunch and enter credentials again.

Example input (also supplied as Computers.example.csv):

```csv
ComputerName
SERVER01
SERVER02.contoso.com
```

## Project files

| File | Purpose |
|---|---|
| Launch.cmd | Launch the live GUI using 64-bit Windows PowerShell. |
| Demo.cmd | Exercise the interface with synthetic data and no remote calls. |
| Start-ServerUpdateValidation.ps1 | GUI, campaign continuation, and bounded workers. |
| Remote.Assessment.ps1 | Target-side readiness, update/reboot, and scan assessment. |
| Validation.Core.ps1 | CSV contract, evidence verification, and report persistence. |
| UI.Theme.ps1 | Native Windows Forms styling and custom controls. |
| UI.Commands.ps1 | Menus, shortcuts, view controls, local help, and row-copy commands. |
| Run-Tests.cmd | Core and mocked remote logic tests. |
| Test-Interface.ps1 | Actual GUI tests using synthetic workers. |
| BUILD-NOTES.md | Build history, test details, and validation boundaries. |
| TROUBLESHOOTING.md | Choosing waves, interpreting pending verification, and recovery guidance. |

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), and
[SECURITY.md](SECURITY.md) for project history, development, and security guidance.
Operational reports, local session files, test artifacts, and ZIPs are excluded
from Git. Only the fictional example CSV belongs in source history.

Names are trimmed, validated as DNS names, and duplicate names are rejected. Extra
columns in a names-only inventory are ignored. IP addresses are not supported by
this Kerberos workflow. Both server and workstation names are accepted.

## Requirements

- 64-bit **Windows PowerShell 5.1**, STA, and built-in .NET Windows Forms. No modules
  are downloaded or installed. PowerShell 7 is not the runtime for this build.
- A domain-connected administrative computer, DNS resolution, and working Kerberos.
- WinRM enabled/reachable on targets, and access to the Microsoft.PowerShell endpoint.
- Credentials permitted to use remote PowerShell, read local HKLM and SCCM WMI/CIM,
  and invoke SMS_Client.TriggerSchedule. An authorized local administrator commonly
  has these rights; the tool does not grant any permissions.
- Writable output folders. Prefer local NTFS report storage for the first pilot.
  Other filesystems/shares must support .NET File.Replace and exclusive file handles.
- Organization-approved execution policy/signatures. Launch.cmd deliberately does
  not bypass policy. If downloaded scripts are blocked, review their contents and
  follow your organization's unblocking/signing procedure. This build is unsigned.

The launchers use Sysnative when invoked from a 32-bit process so the GUI still
runs in 64-bit Windows PowerShell.

## GUI behavior

The interface follows the approved light concept: pale background, rounded section
cards, navy headings, blue primary action/progress, and colored text-labelled status
badges. Windows Forms and built-in GDI+ provide the styling; no external UI library
is installed. Native title bars, file dialogs, and scrollbars follow the host's
Windows version and desktop theme. UI.Theme.ps1 must remain with the other scripts.

- Input CSV, finished CSV, unfinished CSV: text fields and Browse controls.
- Set credentials: separate masked password window; only the username is displayed.
- Concurrent checks: 1-32, default 8. Settings lock while a wave is running.
- Load list: preview the computers before starting any server action.
- After starting, Load list becomes New list and the primary action checks pending
  verification only. Reassess unfinished is a separate button. Both actions reload
  the unfinished report and preserve scan evidence. Skipped findings stay in the
  table and tracking CSV with their prior assessment time. PASS is never rechecked
  implicitly. Progress counts only the computers selected for the current wave.
- Campaign.json stores resume settings beside the reports. Validation-Session.json
  stores the most recent campaign paths and concurrency beside the scripts
  using atomic replacement, with a .bak snapshot. It contains no credentials.
  Demo mode uses separate Demo-Session.json settings. Keep the script folder writable.
  The CSVs are the authoritative computer state; keep all tracking columns intact.
  Missing or invalid saved reports block automatic continuation and display an error.
- When no verification is pending, its action reports the remaining attention count
  without starting workers. Campaign completion requires no unfinished computers.
  New list explicitly begins another assessment cycle.
- Scrollable, sortable results grid with status filter, name search, and a selected
  row detail panel showing the report fields and diagnostic evidence.
- **Unfinished** is the default status filter. Switch to PASS or All as needed.
- Click any colored status total to apply that status filter to Computer status.
  Existing search text remains applied; the View menu checkmark stays synchronized.
- Wave setup and Checks are separate panes. Collapse setup, or use View > Show wave
  setup pane, to reclaim space without hiding the check actions.
- View > Show concurrent check progress toggles the smaller worker bars below overall
  progress. They show actual observed assessment stages with computer name and
  elapsed time; a marquee indicates no progress record has arrived yet. They do not
  measure update-installation percentages or invent progress from elapsed time.
  Each configured worker has a slot; scroll the worker area for additional slots.
  Completion means the check returned, not that the computer passed.
- Hover over fields, buttons, status totals, or worker labels for contextual help.
  Setup-collapse and worker-bar preferences are saved with campaign settings. Changes
  made during a wave are saved after it completes; old session files remain readable.
- **Export Report** offers an Excel workbook (.xlsx) or CSV (.csv). Excel includes
  every campaign computer, regardless of the active filter/search, on separate PASS,
  VERIFICATION PENDING, ACTION REQUIRED, NOT READY, UNABLE TO DETERMINE, QUEUED, and
  CHECKING tabs. Empty categories retain their header row. Headers are frozen and
  filterable; Excel does not need to be installed. CSV exports the filtered and
  searched table, in its current sort order. It contains exactly Computer, Status,
  Reason / current step, Updates, Reboot, and Last checked (UTC). Full reason text
  is retained even when the displayed cell is truncated. The details pane and
  internal tracking fields are excluded. An empty view exports headers only.
  Export runs in the background and cannot overwrite the campaign input, reports,
  or session files. Display exports are for reporting, not next-wave input.
- Progress distinguishes assessed, running, and queued computers. Assessed does not
  mean PASS. A completed wave can still have many unfinished computers.
- Stop after active checks: no new dispatch; active workers finish and queued rows
  remain in unfinished output. Closing during a wave offers the same graceful stop.
- A query has an overall 180-second timeout by default. Cancellation is requested
  asynchronously; underlying WinRM/.NET cancellation can add cleanup time.

## Menus and shortcuts

| Menu | Commands |
|---|---|
| File | New campaign (Ctrl+N), Resume campaign (Ctrl+O), Export Report (Ctrl+E), Open reports folder, Exit (Alt+F4). |
| Actions | Run initial assessment, Check pending verification, Reassess unfinished, Stop after active checks, Set credentials. |
| View | Status filter with active checkmark, Find computer (Ctrl+F), Clear search, Show details pane, Reset view. |
| Help | User guide (F1), Troubleshooting, Release notes, GitHub repository, About. |

Menus and visible buttons share the same underlying operations. Campaign changes
and credentials are unavailable during an active wave. Filtering, searching,
copying, and display export remain available. Exit uses the existing graceful-stop
confirmation if work is active. Opening help does not start assessments or a scan.

Resume campaign opens a saved session JSON and validates settings and both reports
before replacing the current campaign. The selected campaign's paths are saved
locally for the next launch; credentials are never included. Only open session files
you trust, since their report paths are read using your interactive account.

Open reports folder offers separate destinations when the files are stored in
different directories. Help content opens locally in a read-only window. About
shows the installed application, PowerShell, process architecture, and CLR versions.

Right-click a computer to copy its name, six-column status summary, or detailed
results. Copy uses the row you clicked, including sorted/filtered views. Review
computer identifiers and diagnostics before sharing them. Reset view restores
Unfinished, clears search and sorting, and resets column proportions. The details
pane toggle expands the table without changing assessment or export content.

## Responsiveness and concurrency

Remote queries run in bounded worker runspaces. In 1.0.7, tracking report writes
also run in a dedicated background runspace, with only one report writer active.
The UI copies a snapshot and continues processing input while CSV/JSON conversion
and disk writes complete. Dispatch intents are batched; their checkpoint must
finish before the corresponding computers are assessed. A wave remains active
until its final results have been saved. The footer shows checkpoint activity.

Result processing and worker launches are limited per UI timer tick. Summary
updates are throttled, status counts use one pass over the list, and bulk list
loads suppress repeated binding events. Initial CSV parsing and table snapshot
capture still occur on the UI thread; this is not a hard real-time interface.

CPU utilization is not a target percentage. Remote query latency, endpoint/client
performance, report size, and storage latency can limit throughput while the local
machine has spare CPU. Use writable local report storage where practical. Start
with concurrency 8, then compare representative waves at 12 and 16 if appropriate
for your environment; watch timeouts and endpoint load rather than CPU alone.
Increasing process priority or simply packaging the same script as an EXE does
not remove UI-thread work or remote waits. There is no EXE build in this release.

Microsoft's [Windows Forms threading guidance](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/controls/multithreading-in-windows-forms-controls)
explains why time-consuming work belongs off the UI thread. Actual improvements
in your estate still need a live comparison; synthetic responsiveness tests do
not establish production throughput.

## Status meanings

| Status | Meaning |
|---|---|
| QUEUED | Not assessed in this wave; retained if stopped. |
| CHECKING | A worker is assessing the computer. |
| NOT READY | Observed startup/client/update activity prevents assessment; see reason. |
| UNABLE TO DETERMINE | Access, missing/unsupported evidence, unknown compliance, or a query error prevents a reliable result. |
| ACTION REQUIRED | Software Center-visible updates waiting and/or a pending reboot were positively observed. |
| VERIFICATION PENDING | Verification scan requested or earlier request still awaiting usable completion evidence. |
| PASS | Later-wave evidence confirms a valid qualifying scan after the request, with no Software Center-visible updates waiting and no checked pending-reboot indicator. |

## Assessment and verification

The readiness checks require the SCCM client service CcmExec to be running and the
computer to have at least 120 seconds of uptime (a conservative startup guard).
SCCM update states indicating installation or verification in progress yield NOT READY.
Process names such as TiWorker are not used as proof of active servicing.

The project's update authority is **OS/.NET patches visible in Software Center**, plus the
separately checked pending-reboot indicators. The tool uses Software Center's backing
**CCM_SoftwareUpdate** client API under root\ccm\ClientSDK and includes only records
with **UserUIExperience = True**, Microsoft's documented Software Center visibility
flag, followed by explicit title-based scope classification. It does not screen-scrape the application. Software Center's displayed list can
refresh at a different instant from the client API; the report is a point-in-time
assessment of that visible-update scope, not a screenshot comparison.

MissingCount/MissingUpdates describe visible updates with ComplianceState 0. The grid
labels this count **Updates**. Visible updates with indeterminate compliance prevent
a clear assessment. Hidden deployments, including their install/verification states,
are outside the update scope. Known non-OS products are excluded. Unknown titles
yield NOT READY and are listed in ScopeAmbiguousUpdates; they cannot silently pass.
A failed required query or missing visibility flag cannot become a clean zero count.

The broader update store is no longer queried or included in the reports. Its 12
previously observed records do not control this tool. They are neither classified
as prestaged nor deleted as obsolete. No KB/title deduplication hides visible findings.

With zero visible updates waiting and no pending reboot, the first clear wave requests
a scan and reports VERIFICATION PENDING. A later wave can PASS only after qualifying
scan completion evidence and another clear visible-update/reboot assessment.

Reboot authority is limited to in-scope visible update states 8/9/10, Windows CBS
RebootPending, and Windows Update RebootRequired in the 64-bit registry view.
Neither PendingFileRenameOperations nor PendingFileRenameOperations2 is read.
The generic CCM_ClientUtilities reboot method is not called: its flags do not
identify the reboot cause and must not reintroduce PFRO/non-OS findings indirectly.

The client API does not expose a documented product-category field. The local
Get-WindowsPatchScope rules include Windows cumulative/security/servicing updates
and .NET updates; they exclude Office/Microsoft 365 and related products, Defender
definitions, drivers/firmware, MSRT, feature upgrades, and enablement packages.
This is a conservative title-rule contract, not a vendor product-ID classification.
Unrecognized titles require operator review; update the rules only after reviewing
representative titles from your environment. The broad update store remains unused.

VisibleUpdatesFailed, FailedUpdateCount, and FailedUpdates describe in-scope updates
whose EvaluationState is 13 (Error). ErrorCode is included when available. NOT READY
reasons state Yes/No/Unknown for reported failures, even when the client is stopped
or within the startup guard. An unavailable update query yields Unknown, never No.
Failure states in excluded products do not affect this OS/.NET assessment.

After upgrading an existing campaign, run Reassess unfinished to refresh findings
under the new scope, including earlier PFRO-only results. Prior timestamps and
finished results are retained; the application and report-schema versions are separate.

When initial checks are clear, the only state-changing call is **Scan by Update Source**,
SMS_Client.TriggerSchedule `{00000000-0000-0000-0000-000000000113}`. Request success
with an explicit zero return value means accepted, not completed. The tool reports VERIFICATION PENDING
and leaves confirmation for a later wave. It never invokes deployment evaluation,
update installation, reboot, service control, policy reset, cache deletion, or repair.
Existing SCCM policies continue to operate independently and may react to new results.

The unfinished report carries the request time (target UTC), boot time, and per-source
completion baseline. On a later wave, the tool requires all current update sources
to have valid scan-history records, matching source versions, and completion times
strictly later than both the request and previous completion. A boot or source change
keeps the existing request pending with an explicit reason instead of automatically
replacing it. Review VerificationContextJson in the computer details or CSV before
deliberately starting a new verification cycle. It records the loaded request,
saved and observed boot times, baseline, sources, history, and comparison result.
Visible updates waiting
or pending reboots invalidate the earlier request so remediation is followed by new
verification. A pending request is not repeatedly submitted.

The first build reads CCM_UpdateSource and CCM_ScanUpdateSourceHistory for this
evidence, validating expected properties at runtime. These are internal SCCM client
interfaces rather than a guaranteed version-independent public completion contract.
Unsupported class layouts, ambiguous history, or missing evidence prevent PASS and
are exposed for the pilot. Scan history/source metadata is read before and after the
visible-update query; a changing snapshot yields NOT READY. Boot time is also rechecked.

The scan provider response is recorded separately as ScanRequestOutcome and
ScanRequestDetails. A missing, null, blank, or malformed ReturnValue is **Unconfirmed**,
not accepted and not proof that submission failed. It produces VERIFICATION PENDING
with REQUEST UNCONFIRMED. The saved request boundary is retained, and the next wave
does not resubmit. Only newer qualifying scan history can permit PASS. Explicit
nonzero return codes remain failures; thrown submission errors remain failures.
Diagnostics for remote assessment failures now explicitly include the failing stage,
error ID, category, exception type/message, and stack instead of relying on error
display formatting. The reboot-status method still requires usable return/flag data.

TriggerSchedule exposes no correlation token. The tool establishes a qualifying valid
scan after its request; it cannot prove exclusive ownership of that scan if a normal
scheduled scan overlaps. Source history is deliberately required instead of assuming
that a timer, a zero trigger return code, or empty query output proves completion.

## Output, recovery, and security

- **Finished CSV accumulates PASS computers** across waves, one per DNS name. A
  later adverse/current observation replaces any earlier PASS for that same name.
  New campaigns receive unique report folders. Previously passed computers
  not present in the current input are retained with their original timestamps.
- **Unfinished CSV contains everything else**, including queued rows after stopping.
  Reuse it without deleting tracking columns. Sorting/filtering the GUI does not
  change which computers are assessed or saved to tracking reports. CSV display
  export follows the GUI filter/search/sort; Excel includes all campaign rows.
- Existing outputs receive a `.bak` snapshot. Assessment results are checkpointed
  in background batches through temporary files and atomic replacement per file.
  The visible table can briefly be ahead of the tracking CSVs while a save is busy;
  wave completion waits for the final save. The pair is not a single
  transaction: finished is written first, and an interruption can leave a duplicate
  computer across reports. Use timestamps and .bak files during recovery.
- Empty reports contain headers. An empty unfinished report means no computers in
  that wave remain; no further wave is needed for that list.
- Empty `.lock` sidecar files remain beside reports. Their existence is harmless;
  open exclusive handles prevent two instances from writing the same report.
- Durable CHECKING/ATTEMPT IN PROGRESS rows are saved before remote dispatch. If
  the process is killed or times out before a new scan response is recorded, the
  next wave refuses to silently reissue the scan. Review client logs, then use a
  names-only input for that computer to deliberately begin fresh verification.
- If saving fails, new dispatch stops. The GUI reports the problem and retains
  in-memory results while active workers finish. Restore access/free disk space
  so saving can complete; do not forcibly close while results are unsaved. A lost
  remote result may require manual recovery from the last CSV/.bak and client logs.
- Credentials remain in process memory, are never exported, and are not persisted.
  The masked GUI textbox briefly holds password text as ordinary Windows controls
  do; SecureString is not a substitute for a trusted administrative workstation.
- Input/output paths are accessed as the interactive user, not the remote credential.
  Remote workers do not access shares; no credential delegation is configured.
- Report text is escaped against common spreadsheet formula prefixes. Reports still
  contain sensitive infrastructure details: use restricted storage and protect the
  tracking columns from modification. CSV tracking is not cryptographically signed.

## Timestamp format and compatibility

The grid, detail pane, and top-level timestamp columns in both CSVs use
**MMDDYYYY HH:MM:SS**, for example `10262026 14:35:07`. The clock reference remains
**UTC**; this release changes formatting, not time zone. Column names ending in Utc
and the grid's UTC label remain explicit.

Report schema 2 adds a `TrackingJson` column that retains exact original timestamps
for scan ordering and boot identity. Technical scan-evidence JSON also retains its
precise machine-readable values. These metadata columns are not ordinary display
timestamps; do not delete or edit them when reusing unfinished output. The detail
pane omits these JSON fields and shows the formatted values.

Reports from 1.0.0-1.0.3 (schemas 1-3) are accepted and upgraded to schema 4 when saved.
Old MissingCount/MissingUpdates used a broader scope. Their displayed counts are cleared
until reassessed rather than mislabeled as visible updates. Broad-store report fields
are removed. UpdateScope marks legacy observations that have not been reassessed.
Previously accumulated PASS rows retain their original timestamps; include those names
in input if a fresh result under the new scope is wanted. Use this build for subsequent
waves; older versions cannot read schema 4. Keep the automatic .bak for rollback.

If 1.0.3 reported missing ReturnValue after saving ScanRequestedAtUtc, reuse that
unfinished CSV as input. Do not remove the request timestamp to work around the error:
the scan may already have been submitted. This version checks the saved boundary
against newer completion evidence without automatically issuing another request.

## Limits of a PASS

PASS is evidence about this observation, Software Center-visible update records and the
listed reboot indicators. It is not a scan of every Microsoft Update product, proof
that no newer update will appear, proof Windows has finished every servicing task,
or an AD/SQL/IIS/application health check. It does not count future reboot cycles.
This first build has offline and synthetic GUI validation; live SCCM and estate
compatibility need a small pilot before operational reliance.

## Advanced launch options

```powershell
# Increase per-computer timeout; preserve the default two-minute startup guard.
powershell.exe -NoProfile -STA -File .\Start-ServerUpdateValidation.ps1 -TimeoutSeconds 240 -MinimumUptimeSeconds 120
```

The initial assessment includes one automatic verification follow-up after 60 seconds;
Stop cancels this follow-up while retaining the first pass. It does not resubmit an
existing scan request or guarantee PASS. Further waves are operator-initiated.
Demo data is clearly marked and rejected by live workers; start real work from
a names-only inventory and separate report filenames.

## Offline checks

Run **Run-Tests.cmd** for deterministic core and mocked remote-decision tests. To
exercise actual GUI controls, background runspaces, two waves and graceful stop:

```powershell
# Opens only the synthetic demo; saves evidence in a new UI-Test-* directory.
powershell.exe -NoProfile -STA -File .\Test-Interface.ps1
```

## Technical references

- [Microsoft: scan/update-store workflow and undeployed applicability](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/troubleshoot-software-update-management)
- [Microsoft: TriggerSchedule IDs and return codes](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/triggerschedule-method-in-class-sms_client)
- [Microsoft: SCCM client reboot query](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/sdk/determineifrebootpending-method-in-class-ccm_clientutilities)
- [Microsoft: deployed-update ClientSDK scope and evaluation states](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/sdk/ccm_softwareupdate-client-wmi-class)
