# Troubleshooting

## Choosing the next action

- Run initial assessment once for the input list.
- Check pending verification assesses only VERIFICATION PENDING computers. Other
  findings retain their previous result, timestamp, and tracking in the reports.
- Reassess unfinished checks all remaining computers after you investigate or
  remediate issues. PASS computers are excluded from both follow-up actions.
- No verification pending does not necessarily mean the campaign is complete.
  Review the remaining ACTION REQUIRED, NOT READY, UNABLE TO DETERMINE, or queued
  computers and use Reassess unfinished when ready.

## Access denied, incorrect credentials, or connectivity failures

Verify DNS, Kerberos, WinRM access, and the account's permissions on the affected
endpoint. Set corrected credentials between waves, then choose Reassess unfinished.
The application does not enable WinRM or change permissions, authentication,
TrustedHosts, firewall rules, or execution policy.

## Verification remains pending

Inspect Reason, Verification, ScanRequestedAtUtc, and VerificationContextJson.
Keep the existing tracking CSVs and session file.

- PENDING: qualifying completion history has not advanced beyond the request and
  saved baseline. Wait and use Check pending verification again.
- BOOT CHANGED or SOURCE CHANGED: the observed boot/source information differs
  from the saved request. Review the comparison before deliberately beginning
  another verification cycle. The application will not silently submit a new scan.
- EVIDENCE UNAVAILABLE: expected scan-history information is absent, unsupported,
  unreadable, or ambiguous. Review diagnostics and client-side SCCM logs.
- REQUEST UNCONFIRMED: the scan response contained no usable acceptance code.
  This does not prove acceptance or rejection. Later qualifying history is required.
- NO REQUEST during a newly started assessment: no prior request was loaded for
  this computer. Check that you resumed the intended campaign instead of starting
  a fresh list. Existing verification requests must retain their tracking columns.

The history APIs are internal client interfaces. An empty update list alone does
not establish scan completion, and supported layouts may vary across client versions.

## Report save failure or interrupted work

Resolve output permissions, file locks, storage capacity, or connectivity. Prefer
local report storage. Do not edit or delete tracking columns to force a PASS.
After a report failure, recent displayed results may be unsaved; Export current
view can preserve a display snapshot under a separate filename. Reopen after
resolving the error and review the reports and .bak snapshots before continuing.

Durable dispatch intents prevent silent duplicate submissions after interruption.
ATTEMPT IN PROGRESS may require client-log review. Begin a fresh verification cycle
only after determining that doing so is appropriate for the affected computer.

## Resume campaign

File > Resume campaign opens a Validation-Session.json file. The reports referenced
by that file must still exist. The original inventory may be archived after the
campaign starts. If the working folder or reports have moved, review the saved paths.
Invalid sessions are rejected before replacing the current campaign. Credentials
are never saved and must be entered again after restarting the application.

## GUI and exports

View > Reset view restores Unfinished, clears the search, and resets sorting and
column proportions. View > Show details pane toggles the lower evidence panel.
Export current view follows the visible filter, search, and sort; it is a reporting
snapshot with six columns, not a tracking file suitable for campaign recovery.

Use File > Open reports folder for each output location. A .lock file can remain
after exit; an open exclusive handle, not file existence, determines whether the
report is locked. Do not delete lock files while another instance may be running.

## Performance

Keep report storage local where practical. Compare representative waves at modest
concurrency before increasing it; monitor timeouts and endpoint load. Background
checkpointing keeps report serialization off the UI thread, but initial file
loading and snapshot capture still take time. CPU percentage alone is not a
throughput target. A simple EXE wrapper would retain the same processing behavior.

## Sharing diagnostics

Right-click the affected computer to copy its name, six-column status summary, or
detailed results. Clipboard copies can include server identifiers and diagnostics;
review and sanitize them before sharing. Never include credentials or real
inventories in public issues. See SECURITY.md for the full security boundaries.
