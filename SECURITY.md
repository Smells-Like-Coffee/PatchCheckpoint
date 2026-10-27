# Security and operational boundaries

## Credentials and access

Credentials are entered through a masked local GUI and retained in process memory.
They are not written to the session settings, CSV reports, or command line. The
masked password control necessarily holds password text briefly in memory; use a
trusted administrative workstation and close the application when finished.

Remote access uses Kerberos through WinRM. The application does not enable WinRM,
modify TrustedHosts, grant permissions, change execution policy, or delegate
credentials to shares. Use an account with the required organizational permissions.

## Remote actions

Assessment reads Software Center-visible update state, reboot indicators, client
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

## Reporting a problem

Report security concerns privately to the repository owner. Do not post credentials,
real inventories, or sensitive diagnostic output in issues. Provide a sanitized
reproduction, affected version, expected behavior, and actual result. Contact the
owner before sharing exploit details publicly.

This repository does not establish a vulnerability-response service or SLA.
