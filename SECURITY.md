# Patch Checkpoint security and operational boundaries

## Credentials and access

Credentials are entered through a masked local GUI and retained in process memory.
They are not written to the session settings, CSV reports, or command line. The
masked password control necessarily holds password text briefly in memory; use a
trusted administrative workstation and close the application when finished.

Remote access uses Kerberos through WinRM. The application does not enable WinRM,
modify TrustedHosts, grant permissions, change execution policy, or delegate
credentials to shares. Use an account with the required organizational permissions.

## Remote actions

Assessment reads Software Center-visible Windows OS/.NET patch state, strict OS
reboot indicators (excluding PFRO/PFRO2 and unattributed SCCM flags), client
readiness, and scan evidence. The sole remote state change is an SCCM client scan
request through SMS_Client.TriggerSchedule, schedule 113. Existing SCCM policy can
react independently to new scan results. The application does not install updates
or restart computers.

## Sensitive local data

Operational CSVs contain computer names and patch/reboot information. Session JSON
contains local report paths. Store the working folder and reports with appropriate
NTFS/share permissions. Backups contain previous report data and need the same
protection. Git ignore rules exclude operational reports and session settings;
they are not an access-control mechanism.

CSV display fields are escaped against spreadsheet formula interpretation. Treat
external files as untrusted and retain all verification tracking columns.
Only open saved campaign JSON files you trust: their referenced report paths are
read using your interactive account. Resume validates the data before switching
campaigns and never executes saved code. Row-copy commands place selected server
identifiers and diagnostics on the system clipboard only at your request; review
and sanitize that content before sharing it outside your organization.

## Reporting a problem

Help > Diagnostic Export creates a local, unencrypted support ZIP containing full
campaign rows, scan evidence, saved report CSVs/backups, local runtime/settings and
recent application messages. It is not anonymized. Review its contents and use a
trusted sharing channel; never attach an operational bundle to a public issue.
The collector uses an explicit field/file list and does not collect credential
objects, environment dumps, memory dumps, raw session JSON or arbitrary folder files.
It performs no endpoint queries. Existing diagnostic/report text is included as data.

Report security concerns privately to the repository owner. Do not post credentials,
real inventories, or sensitive diagnostic output in issues. Provide a sanitized
reproduction, affected version, expected behavior, and actual result. Contact the
owner before sharing exploit details publicly.

This repository does not establish a vulnerability-response service or SLA.
