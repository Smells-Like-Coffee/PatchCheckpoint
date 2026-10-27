# Changelog

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
