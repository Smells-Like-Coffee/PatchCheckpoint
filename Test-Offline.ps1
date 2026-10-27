#requires -Version 5.1
<#
.SYNOPSIS
    Runs deterministic offline checks of the validation and CSV contract.
.DESCRIPTION
    Uses temporary local files and synthetic observations. Executes no remote
    commands and submits no scans. Tests fail with a terminating error.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$helpers = [IO.File]::ReadAllText((Join-Path $testRoot 'Validation.Core.ps1'))
. ([scriptblock]::Create($helpers))
$script:assertions = 0
function Assert-Equal {
    param($Actual,$Expected,[string]$Message)
    if ($Actual -ne $Expected) { throw "$Message : expected '$Expected'; actual '$Actual'." }
    $script:assertions++; Write-Output "PASS: $Message"
}
$sources = @([pscustomobject]@{ Id = 'SOURCE-A'; Version = '7' })
$baseline = @([pscustomobject]@{ Id = 'SOURCE-A'; Version = '7'; CompletedUtc = '2026-01-01T00:00:00Z' })
$history = @([pscustomobject]@{ Id = 'SOURCE-A'; Version = '7'; Valid = $true; CompletedUtc = '2026-01-01T02:00:00Z' })
$r = New-ValidationRow 'SERVER01'
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-31T00:00:00Z') 'NO REQUEST' 'Initial clear assessment cannot pass'
$r.ScanRequestedAtUtc = '2026-01-01T01:00:00Z'; $r.ScanRequestBootUtc = '2025-12-31T00:00:00Z'
$r.ScanBaselineJson = ConvertTo-Json -InputObject $baseline -Compress
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-31T00:00:00Z') 'CONFIRMED' 'New valid scan qualifies'
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-30T00:00:00Z') 'BOOT CHANGED' 'Reboot invalidates verification'
$history[0].Valid = $false
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-31T00:00:00Z') 'PENDING' 'Invalid history cannot pass'
$history[0].Valid = $true; $history[0].CompletedUtc = '2026-01-01T01:00:00Z'
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-31T00:00:00Z') 'PENDING' 'Completion must be strictly after request'
$history[0].CompletedUtc = '2026-01-01T02:00:00Z'
$sources[0].Version = '8'
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-31T00:00:00Z') 'SOURCE CHANGED' 'Catalog change requires fresh verification'
$sources[0].Version = '7'
Assert-Equal (Test-ScanVerification $r $sources @() '2025-12-31T00:00:00Z') 'EVIDENCE UNAVAILABLE' 'Absent history cannot pass'
$r.ScanBaselineJson = 'not JSON'
Assert-Equal (Test-ScanVerification $r $sources $history '2025-12-31T00:00:00Z') 'EVIDENCE UNAVAILABLE' 'Malformed carry-forward state cannot pass'
$r.ScanBaselineJson = ConvertTo-Json -InputObject $baseline -Compress
$r.Reason = '=HYPERLINK("bad")'
Assert-Equal ((ConvertTo-SafeCsvRow $r).Reason.StartsWith("'=")) $true 'Spreadsheet formula text is escaped'

# Human-readable timestamps must not erase the exact scan request/boot values.
$precise = New-ValidationRow 'PRECISE01'
$precise.CheckedAtUtc = '2026-10-26T14:35:07.1234567Z'
$precise.LastBootUtc = '2026-10-26T10:15:00.9876543Z'
$precise.ScanRequestedAtUtc = '2026-10-26T14:00:00.4567890Z'
$precise.ScanRequestBootUtc = $precise.LastBootUtc
$exported = ConvertTo-SafeCsvRow $precise
Assert-Equal $exported.CheckedAtUtc '10262026 14:35:07' 'Report timestamp follows MMDDYYYY HH:MM:SS'
Assert-Equal (Format-ValidationTimestamp '2026-10-26T10:35:07-04:00') '10262026 14:35:07' 'Formatting keeps UTC as the clock reference'
$restored = ConvertTo-ValidationRow $exported
Assert-Equal $restored.CheckedAtUtc $precise.CheckedAtUtc 'Exact assessment timestamp survives report conversion'
Assert-Equal $restored.ScanRequestedAtUtc $precise.ScanRequestedAtUtc 'Exact scan request boundary survives report conversion'
Assert-Equal $restored.ScanRequestBootUtc $precise.ScanRequestBootUtc 'Exact boot identity survives report conversion'
Assert-Equal ((Format-ValidationDetails $precise) -match '10262026 14:35:07') $true 'Detail pane uses formatted timestamps'
Assert-Equal ((Format-ValidationDetails $precise) -match 'TrackingJson') $false 'Detail pane omits internal timestamp metadata'
$exported.CheckedAtUtc = '10272026 14:35:07'
$rejected = $false; try { ConvertTo-ValidationRow $exported | Out-Null } catch { $rejected = $true }
Assert-Equal $rejected $true 'Edited visible timestamps cannot contradict tracking'
$legacy = [pscustomobject]@{ SchemaVersion = '1'; ComputerName = 'LEGACY01'; CheckedAtUtc = $precise.CheckedAtUtc }
Assert-Equal (ConvertTo-ValidationRow $legacy).CheckedAtUtc $precise.CheckedAtUtc 'Version 1.0.0 ISO report timestamps remain readable'
$oldScope = [pscustomobject]@{ SchemaVersion = '2'; ComputerName = 'LEGACY02'; MissingCount = '12'; MissingUpdates = 'Old broad-store findings' }
$upgraded = ConvertTo-ValidationRow $oldScope
Assert-Equal $upgraded.MissingCount '' 'Legacy broad count is not mislabeled as deployed updates'
Assert-Equal ($upgraded.PSObject.Properties.Name -contains 'UpdateStoreMissingCount') $false 'Broad-store counts are excluded from current reports'
Assert-Equal $upgraded.UpdateScope 'Previous assessment scope; reassessment required' 'Old count scope requires reassessment'
Assert-Equal $upgraded.SchemaVersion '4' 'Updated report schema records Software Center-visible scope'

# A missing acknowledgement can never authorize PASS or a duplicate submission.
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{ ReturnValue = 0 })).Outcome 'Accepted' 'Explicit zero acknowledgement accepted'
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{ ReturnValue = 5 })).Outcome 'Rejected' 'Explicit failure acknowledgement rejected'
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{ ReturnValue = -1 })).Outcome 'Rejected' 'Signed failure acknowledgement is not success'
Assert-Equal (Get-ScanRequestAcknowledgement $null).Outcome 'Unconfirmed' 'No response preserves uncertainty'
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{})).Outcome 'Unconfirmed' 'Missing ReturnValue preserves uncertainty'
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{ ReturnValue = $null })).Outcome 'Unconfirmed' 'Null ReturnValue preserves uncertainty'
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{ ReturnValue = '' })).Outcome 'Unconfirmed' 'Blank ReturnValue preserves uncertainty'
Assert-Equal (Get-ScanRequestAcknowledgement ([pscustomobject]@{ ReturnValue = 'invalid' })).Outcome 'Unconfirmed' 'Malformed ReturnValue is not accepted'
Assert-Equal (Get-ScanRequestAcknowledgement @([pscustomobject]@{ ReturnValue = 0 },[pscustomobject]@{ ReturnValue = 0 })).Outcome 'Unconfirmed' 'Ambiguous multiple responses are not accepted'

# Reproduce the timestamp/source shape supplied during the live pilot. The source
# identifier is anonymized; precise timestamps and version preserve the test case.
$savedCase = New-ValidationRow 'SAVED-REQUEST01'
$savedCase.CheckedAtUtc = '2026-10-27T14:17:12.0226938Z'
$savedCase.LastBootUtc = '2026-10-23T04:25:19.4881440Z'
$savedCase.ScanRequestedAtUtc = '2026-10-27T14:17:12.9457535Z'
$savedCase.ScanRequestBootUtc = $savedCase.LastBootUtc
$savedBaseline = @([pscustomobject]@{ Id = '{SOURCE-SAVED}'; Version = '1535'; CompletedUtc = '2026-10-27T14:16:30.0490000Z' })
$savedCase.ScanBaselineJson = ConvertTo-Json -InputObject $savedBaseline -Compress
$savedCsv = ConvertTo-SafeCsvRow $savedCase | ConvertTo-Csv -NoTypeInformation
$savedRestored = ConvertTo-ValidationRow ($savedCsv | ConvertFrom-Csv)
$savedSources = @([pscustomobject]@{ Id = '{SOURCE-SAVED}'; Version = '1535' })
$savedHistory = @([pscustomobject]@{ Id = '{SOURCE-SAVED}'; Version = '1535'; Valid = $true; CompletedUtc = '2026-10-27T14:16:30.0490000Z' })
Assert-Equal $savedRestored.ScanRequestedAtUtc $savedCase.ScanRequestedAtUtc 'Pilot request timestamp survives formatted CSV import exactly'
Assert-Equal $savedRestored.ScanRequestBootUtc $savedCase.ScanRequestBootUtc 'Pilot boot identity survives formatted CSV import exactly'
Assert-Equal (Test-ScanVerification $savedRestored $savedSources $savedHistory $savedRestored.LastBootUtc) 'PENDING' 'Pilot scan completion before latest request cannot PASS'
$savedHistory[0].CompletedUtc = '2026-10-27T14:18:00.0000000Z'
Assert-Equal (Test-ScanVerification $savedRestored $savedSources $savedHistory $savedRestored.LastBootUtc) 'CONFIRMED' 'Pilot request confirms when newer valid completion appears'

# Multiple update sources must survive JSON/CSV import in Windows PowerShell 5.1.
# Matching sources may arrive in a different order; actual version changes still block.
$multi = ConvertTo-ValidationRow $savedRestored
$multiBaseline = @(
    [pscustomobject]@{ Id = 'SOURCE-A'; Version = '7'; CompletedUtc = '2026-10-27T14:16:00Z' }
    [pscustomobject]@{ Id = 'SOURCE-B'; Version = '9'; CompletedUtc = '2026-10-27T14:16:00Z' }
)
$multi.ScanBaselineJson = ConvertTo-Json -InputObject $multiBaseline -Compress
$multi = ConvertTo-ValidationRow ((ConvertTo-SafeCsvRow $multi | ConvertTo-Csv -NoTypeInformation) | ConvertFrom-Csv)
$multiSources = @([pscustomobject]@{ Id = 'SOURCE-B'; Version = '9' }, [pscustomobject]@{ Id = 'SOURCE-A'; Version = '7' })
$multiHistory = @($multiSources | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Version = $_.Version; Valid = $true; CompletedUtc = '2026-10-27T14:18:00Z' } })
Assert-Equal (Test-ScanVerification $multi $multiSources $multiHistory $multi.LastBootUtc) 'CONFIRMED' 'Multiple sources confirm after JSON and CSV round trip regardless of order'
Assert-Equal (Test-ScanVerification $multi $multiSources @($multiHistory[0]) $multi.LastBootUtc) 'EVIDENCE UNAVAILABLE' 'Every source requires completion evidence'
$multiSources[0].Version = '10'
Assert-Equal (Test-ScanVerification $multi $multiSources $multiHistory $multi.LastBootUtc) 'SOURCE CHANGED' 'Actual multi-source version change still blocks confirmation'

$folder = Join-Path $testRoot ('ServerValidationTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
try {
    $inputPath = Join-Path $folder 'input.csv'; $finishedPath = Join-Path $folder 'finished.csv'; $unfinishedPath = Join-Path $folder 'unfinished.csv'
    [IO.File]::WriteAllText($inputPath,"ComputerName`r`nSERVER01`r`nSERVER02`r`n")
    $rows = @(Read-ValidationInput $inputPath)
    Assert-Equal $rows.Count 2 'Names-only input accepted'
    $rows[0].Status = 'PASS'; $rows[1].Status = 'VERIFICATION PENDING'; $rows[1].ScanRequestedAtUtc = $r.ScanRequestedAtUtc; $rows[1].ScanBaselineJson = $r.ScanBaselineJson
    $finished = @{}
    Save-WaveReports $rows $finished $finishedPath $unfinishedPath
    Assert-Equal @(Import-Csv -LiteralPath $finishedPath).Count 1 'PASS goes to finished report'
    Assert-Equal @(Import-Csv -LiteralPath $unfinishedPath).Count 1 'Pending goes to unfinished report'
    $nextWave = @(Read-ValidationInput $unfinishedPath)
    Assert-Equal $nextWave[0].ScanRequestedAtUtc $rows[1].ScanRequestedAtUtc 'Formatted CSV request restores exact value in next wave'
    Assert-Equal $nextWave[0].ScanBaselineJson $r.ScanBaselineJson 'Verification JSON survives CSV round trip'
    $nextWave[0].Status = 'PASS'; Save-WaveReports $nextWave $finished $finishedPath $unfinishedPath
    Assert-Equal @(Import-Csv -LiteralPath $finishedPath).Count 2 'Finished report accumulates PASS rows'
    Assert-Equal @(Import-Csv -LiteralPath $unfinishedPath).Count 0 'Empty unfinished report retains valid header'
    Assert-Equal ([IO.File]::Exists($finishedPath + '.bak')) $true 'Previous snapshot backed up'
    $nextWave[0].Status = 'ACTION REQUIRED'; Save-WaveReports $nextWave $finished $finishedPath $unfinishedPath
    Assert-Equal @(Import-Csv -LiteralPath $finishedPath).Count 1 'New adverse result removes earlier PASS'
    [IO.File]::WriteAllText($inputPath,"ComputerName`r`nSERVER01`r`nserver01`r`n")
    $rejected = $false; try { Read-ValidationInput $inputPath | Out-Null } catch { $rejected = $true }
    Assert-Equal $rejected $true 'Conflicting duplicate names rejected'
    [IO.File]::WriteAllText($inputPath,"ComputerName`r`n192.168.1.10`r`n")
    $rejected = $false; try { Read-ValidationInput $inputPath | Out-Null } catch { $rejected = $true }
    Assert-Equal $rejected $true 'IP targets rejected for Kerberos workflow'
    $statusPath = Join-Path $folder 'status.csv'
    $columns = @('Computer','Status','Reason / current step','Updates','Reboot','Last checked (UTC)')
    $displayRows = @([pscustomobject][ordered]@{ Computer = 'SERVER02'; Status = 'ACTION REQUIRED'; 'Reason / current step' = '=formula, with comma'; Updates = '2'; Reboot = 'No'; 'Last checked (UTC)' = '10272026 14:50:26' })
    Save-StatusCsv $statusPath $columns $displayRows
    $export = @(Import-Csv -LiteralPath $statusPath)
    Assert-Equal $export.Count 1 'Status snapshot exports the supplied row count'
    Assert-Equal ($export[0].PSObject.Properties.Name -join '|') ($columns -join '|') 'Status snapshot has exactly the six displayed headers'
    Assert-Equal $export[0].'Reason / current step' "'=formula, with comma" 'Status export escapes formulas and preserves quoted commas'
    Assert-Equal $export[0].'Last checked (UTC)' '10272026 14:50:26' 'Status export retains displayed timestamp format'
    Save-StatusCsv $statusPath $columns @()
    Assert-Equal @(Import-Csv -LiteralPath $statusPath).Count 0 'Empty status view exports a header-only CSV'
    Assert-Equal ([IO.File]::Exists($statusPath + '.bak')) $true 'Replacing an export retains the previous snapshot'
    $lock = [IO.File]::Open(($unfinishedPath + '.lock'),'OpenOrCreate','ReadWrite','None')
    try {
        $rejected = $false
        try { $other = [IO.File]::Open(($unfinishedPath + '.lock'),'OpenOrCreate','ReadWrite','None'); $other.Dispose() } catch { $rejected = $true }
        Assert-Equal $rejected $true 'Report lock prevents simultaneous writers'
    }
    finally { $lock.Dispose() }
}
finally {
    # Only known test files are removed; never recurse into a computed directory.
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -File)) { Remove-Item -LiteralPath $file.FullName }
    [IO.Directory]::Delete($folder)
}
Write-Output "Offline checks passed: $script:assertions"
