<#
.SYNOPSIS
    Shared data, verification, and report functions for Server Update Validation.
.DESCRIPTION
    Defines the CSV contract, validates carried-forward scan evidence, and writes
    recoverable report snapshots. It performs no remote actions when loaded.
#>

# Use a fixed schema so both reports can be used as input without losing state.
function New-ValidationRow {
    param([string]$ComputerName)
    [pscustomobject][ordered]@{
        SchemaVersion = '4'; ComputerName = $ComputerName; Status = 'QUEUED'
        Reason = 'Waiting for a worker'; CheckedAtUtc = ''; MissingCount = ''
        MissingUpdates = ''; UpdateScope = 'Software Center-visible Windows OS and .NET patches'
        RebootScope = 'Strict patching/OS; PFRO ignored'
        VisibleUpdatesFailed = 'Unknown'; FailedUpdateCount = ''; FailedUpdates = ''
        ScopeExcludedCount = ''; ScopeAmbiguousCount = ''; ScopeAmbiguousUpdates = ''
        RebootPending = 'Unknown'; RebootReasons = ''
        LastBootUtc = ''; UptimeMinutes = ''; ClientService = 'Unknown'
        ScanRequestedAtUtc = ''; ScanRequestBootUtc = ''; ScanBaselineJson = ''
        ScanRequestOutcome = ''; ScanRequestDetails = ''
        ScanEvidenceJson = ''; Verification = ''; VerificationContextJson = ''; Diagnostics = ''; TrackingJson = ''
    }
}

# Copy only known fields; CSV content is data and is never evaluated as code.
function ConvertTo-ValidationRow {
    param($InputRow)
    $row = New-ValidationRow ([string]$InputRow.ComputerName).Trim()
    foreach ($field in $row.PSObject.Properties.Name) {
        if ($InputRow.PSObject.Properties.Name -contains $field) {
            $row.$field = [string]$InputRow.$field
        }
    }
    $row.ComputerName = $row.ComputerName.Trim()
    # Visible timestamps are rounded to seconds. Restore exact values only from
    # matching tracking data so CSV round trips do not change boot/scan comparisons.
    if ($row.TrackingJson) {
        try {
            $tracking = $row.TrackingJson | ConvertFrom-Json -ErrorAction Stop
            foreach ($field in @('CheckedAtUtc','LastBootUtc','ScanRequestedAtUtc','ScanRequestBootUtc')) {
                if ($tracking.PSObject.Properties.Name -notcontains $field) { throw "Missing tracking field $field." }
                $exact = [string]$tracking.$field
                if ($row.$field -ne $exact -and $row.$field -ne (Format-ValidationTimestamp $exact)) {
                    throw "Displayed timestamp differs from its tracking value: $field."
                }
                $row.$field = $exact
            }
        }
        catch { throw "Invalid timestamp tracking for '$($row.ComputerName)': $($_.Exception.Message)" }
    }
    elseif ($row.SchemaVersion -in @('2','3','4') -and @($row.CheckedAtUtc,$row.LastBootUtc,$row.ScanRequestedAtUtc,$row.ScanRequestBootUtc | Where-Object { $_ -match '^\d{8} ' }).Count) {
        throw "Timestamp tracking is missing for '$($row.ComputerName)'. Retain the TrackingJson column when reusing reports."
    }
    $row.TrackingJson = ''
    if ($InputRow.PSObject.Properties.Name -contains 'RebootPending' -and $InputRow.PSObject.Properties.Name -notcontains 'RebootScope') {
        $row.RebootScope = 'Previous reboot scope; reassessment required'
    }
    # Previous scopes included broad-store records or hidden deployments. Do not
    # display an old count as the number of Software Center-visible updates.
    if ($InputRow.PSObject.Properties.Name -contains 'MissingCount' -and
        ($InputRow.PSObject.Properties.Name -notcontains 'UpdateScope' -or
         $InputRow.UpdateScope -ne 'Software Center-visible Windows OS and .NET patches')) {
        $row.MissingCount = ''; $row.MissingUpdates = ''
        $row.UpdateScope = 'Previous assessment scope; reassessment required'
    }
    $row.SchemaVersion = '4'
    $row
}

# ClientSDK exposes names, not a product-category contract. These conservative
# title rules define the agreed OS/.NET scope; unknown titles require review.
function Get-WindowsPatchScope {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'Ambiguous' }
    if ($Name -match '(?i)\b(Office|Microsoft 365|Microsoft365|M365|Excel|Word|PowerPoint|Outlook|OneNote|Visio|Project|SharePoint|Exchange|SQL Server|Microsoft Edge|Teams|OneDrive|Visual Studio|Visual C\+\+|Silverlight|Defender|Security Intelligence|Endpoint Protection|Malicious Software Removal Tool|MSRT|drivers?|firmware)\b|Feature\s+(update|upgrade)|Upgrade\s+to\s+Windows|\benablement package\b') { return 'Excluded' }
    $hasUpdateKind = $Name -match '(?i)\b(Update|Rollup|Hotfix|Servicing Stack|Security Patch)\b'
    $windowsTarget = '(?:Microsoft Windows\b|Windows\s+(?:Server|[0-9]|Vista|XP)|Microsoft server operating system\b)'
    $hasPatchHeading = $Name -match '(?i)^(?:\d{4}-\d{2}\s+)?(?:(?:Cumulative|Security|Critical|Servicing Stack|Monthly|Quality|Preview(?:\s+of)?|Dynamic|Safe OS|Only)\s+)*(?:Update|Rollup|Hotfix)\b'
    $hasWindowsProduct = ($hasPatchHeading -and $Name -match ('(?i)(?:Update|Rollup|Hotfix)(?:\s+Preview)?\s+(?:for|to)\s+' + $windowsTarget)) -or $Name -match ('(?i)^(?:\d{4}-\d{2}\s+)?' + $windowsTarget)
    $hasDotNetProduct = $Name -match '(?i)^(?:Microsoft\s+)?\.NET\b' -or ($hasPatchHeading -and $Name -match '(?i)(?:Update|Rollup|Hotfix)(?:\s+Preview)?\s+for\s+(?:Microsoft\s+)?\.NET\b')
    if ($hasUpdateKind -and ($hasWindowsProduct -or $hasDotNetProduct)) { return 'Included' }
    'Ambiguous'
}

function Read-ValidationInput {
    param([string]$Path, [switch]$AllowEmpty)
    $items = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    if (-not $items.Count -and $AllowEmpty) {
        $reader = [IO.StreamReader]::new([IO.Path]::GetFullPath($Path))
        try { $header = $reader.ReadLine() } finally { $reader.Dispose() }
        if ($header -like '*"ComputerName"*' -and $header -like '*"TrackingJson"*') { return }
        throw 'Empty tracking report has an invalid header.'
    }
    if (-not $items.Count -or $items[0].PSObject.Properties.Name -notcontains 'ComputerName') {
        throw 'Use a nonempty comma-delimited CSV with a ComputerName header.'
    }
    $seen = @{}
    foreach ($item in $items) {
        $row = ConvertTo-ValidationRow $item
        $ip = $null
        if ($row.ComputerName.Length -gt 253 -or
            $row.ComputerName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$' -or
            [Net.IPAddress]::TryParse($row.ComputerName, [ref]$ip)) {
            throw "Invalid computer name '$($row.ComputerName)'. Use DNS names, not IP addresses."
        }
        if ($seen.ContainsKey($row.ComputerName)) {
            throw "Duplicate computer '$($row.ComputerName)'. Remove duplicates to avoid conflicting scan state."
        }
        if ($item.PSObject.Properties.Name -contains 'SchemaVersion' -and $item.SchemaVersion -notin @('1','2','3','4')) {
            throw "Unsupported tracking schema for $($row.ComputerName)."
        }
        $seen[$row.ComputerName] = $true
        $row
    }
}

# Select work without changing any row. Skipped findings remain part of the full
# campaign snapshot and keep their original reason, timestamps, and scan tracking.
function Get-ValidationWorkIndices {
    param([object[]]$Rows, [ValidateSet('Initial','Verification','Unfinished')][string]$Mode)
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        if ($Mode -eq 'Initial' -or
            ($Mode -eq 'Verification' -and $Rows[$index].Status -eq 'VERIFICATION PENDING') -or
            ($Mode -eq 'Unfinished' -and $Rows[$index].Status -ne 'PASS')) { $index }
    }
}

# Validate a saved campaign completely before the GUI switches away from its
# current list. JSON is parsed as data; no saved command or code is executed.
function Read-ValidationCampaign {
    param([string]$Path)
    $saved = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText([IO.Path]::GetFullPath($Path))) -ErrorAction Stop
    foreach ($field in @('Version','InputPath','FinishedPath','UnfinishedPath','Concurrency')) {
        if ($saved.PSObject.Properties.Name -notcontains $field) { throw "Saved campaign is missing $field." }
    }
    $concurrency = 0
    if ($saved.Version -ne 1 -or -not [int]::TryParse([string]$saved.Concurrency,[ref]$concurrency) -or $concurrency -lt 1 -or $concurrency -gt 32) { throw 'Invalid session settings.' }
    foreach ($field in @('InputPath','FinishedPath','UnfinishedPath')) {
        if (-not [string]$saved.$field) { throw "Saved campaign has no $field." }
        $saved.$field = [IO.Path]::GetFullPath([string]$saved.$field)
    }
    if ($saved.FinishedPath -eq $saved.UnfinishedPath -or $saved.FinishedPath -eq $saved.InputPath) { throw 'Saved campaign report paths conflict.' }
    foreach ($reportPath in @($saved.FinishedPath,$saved.UnfinishedPath)) {
        if (-not [IO.File]::Exists($reportPath) -or [IO.Path]::GetExtension($reportPath) -ne '.csv') { throw 'Saved report is missing or invalid.' }
    }
    $finished = @{}
    foreach ($row in @(Read-ValidationInput $saved.FinishedPath -AllowEmpty)) {
        if ($row.Status -ne 'PASS') { throw 'Saved finished report contains a non-PASS row.' }
        $finished[$row.ComputerName] = $row
    }
    $rows = @(Read-ValidationInput $saved.UnfinishedPath -AllowEmpty)
    foreach ($row in $rows) {
        if ($row.Status -notin @('QUEUED','CHECKING','VERIFICATION PENDING','ACTION REQUIRED','NOT READY','UNABLE TO DETERMINE')) { throw "Invalid unfinished status for $($row.ComputerName)." }
    }
    [pscustomobject]@{ Settings = $saved; Rows = $rows; Finished = $finished }
}

# Keep UTC as the clock reference; change only presentation. Parse ISO values with
# invariant culture so workstation locale cannot swap month/day or alter tracking.
function Format-ValidationTimestamp {
    param([AllowEmptyString()][string]$Value)
    if (-not $Value) { return '' }
    $stamp = [datetimeoffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture)
    $stamp.UtcDateTime.ToString('MMddyyyy HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
}

function Format-ValidationDetails {
    param($Row)
    $view = ConvertTo-SafeCsvRow $Row
    $fields = @($view.PSObject.Properties.Name | Where-Object { $_ -notin @('SchemaVersion','TrackingJson','ScanBaselineJson','ScanEvidenceJson') })
    ($view | Select-Object -Property $fields | Format-List * | Out-String).Trim()
}

function Clear-VerificationRequest {
    param($Row)
    $Row.ScanRequestedAtUtc = ''; $Row.ScanRequestBootUtc = ''; $Row.ScanBaselineJson = ''
    $Row.ScanRequestOutcome = ''; $Row.ScanRequestDetails = ''
}

# A missing/blank provider return value is NOT success and is NOT proof that no
# scan was requested. Keep it unconfirmed and require later scan-history evidence.
# Never retry the method automatically based on its response shape.
function Get-ScanRequestAcknowledgement {
    param([AllowNull()]$Response)
    $items = @($Response | Where-Object { $null -ne $_ })
    $result = [pscustomobject]@{ Outcome = 'Unconfirmed'; Code = ''; Details = "SMS_Client.TriggerSchedule response objects: $($items.Count)." }
    if ($items.Count -ne 1) { return $result }
    $item = $items[0]
    $names = @($item.PSObject.Properties | ForEach-Object Name) -join ', '
    $result.Details += " Type: $($item.GetType().FullName). Properties: $names."
    $property = $item.PSObject.Properties['ReturnValue']
    if ($null -eq $property) { $result.Details += ' ReturnValue is absent; acceptance is unconfirmed.'; return $result }
    $value = $property.Value
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        $result.Details += ' ReturnValue is null/blank; acceptance is unconfirmed.'; return $result
    }
    $code = [long]0
    if (-not [long]::TryParse([string]$value,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$code)) {
        $result.Details += " ReturnValue is not an integer: $value. Acceptance is unconfirmed."; return $result
    }
    $result.Code = $code.ToString([Globalization.CultureInfo]::InvariantCulture)
    $result.Outcome = if ($code -eq 0) { 'Accepted' } else { 'Rejected' }
    $result.Details += " ReturnValue: $code. Outcome: $($result.Outcome)."
    $result
}

# Require every configured source to have a valid completion newer than its
# recorded baseline AND the request. Both timestamps use the target's UTC clock.
# A request ID is not exposed by TriggerSchedule; this proves a qualifying scan
# after our request, not exclusive ownership of the scan.
function Test-ScanVerification {
    param($Row, [object[]]$Sources, [object[]]$History, [string]$BootUtc)
    if (-not $Row.ScanRequestedAtUtc) { return 'NO REQUEST' }
    try {
        $requested = [datetimeoffset]::Parse($Row.ScanRequestedAtUtc).UtcDateTime
        if ($Row.ScanRequestBootUtc -ne $BootUtc) { return 'BOOT CHANGED' }
        # Windows PowerShell 5.1 can emit a JSON array as one pipeline object.
        # Assign first, then enumerate its entries so multiple sources do not
        # become one nested array and falsely compare as a changed source set.
        $parsedBaseline = ConvertFrom-Json -InputObject $Row.ScanBaselineJson -ErrorAction Stop
        $baseline = @($parsedBaseline)
        if (-not $Sources.Count -or -not $baseline.Count) { return 'EVIDENCE UNAVAILABLE' }
        $sourceIds = @($Sources | ForEach-Object { [string]$_.Id } | Sort-Object -Unique)
        $oldIds = @($baseline | ForEach-Object { [string]$_.Id } | Sort-Object -Unique)
        if (@(Compare-Object $sourceIds $oldIds).Count) { return 'SOURCE CHANGED' }
        foreach ($source in $Sources) {
            $old = @($baseline | Where-Object { $_.Id -eq $source.Id })
            $current = @($History | Where-Object { $_.Id -eq $source.Id })
            if ($old.Count -ne 1 -or $current.Count -ne 1) { return 'EVIDENCE UNAVAILABLE' }
            if ([string]$old[0].Version -ne [string]$source.Version) { return 'SOURCE CHANGED' }
            if ($current[0].Valid -ne $true -or [string]$current[0].Version -ne [string]$source.Version -or -not $current[0].CompletedUtc) {
                return 'PENDING'
            }
            $completed = [datetimeoffset]::Parse($current[0].CompletedUtc).UtcDateTime
            if ($completed -le $requested) { return 'PENDING' }
            if ($old[0].CompletedUtc -and $completed -le [datetimeoffset]::Parse($old[0].CompletedUtc).UtcDateTime) { return 'PENDING' }
        }
        return 'CONFIRMED'
    }
    catch { return 'EVIDENCE UNAVAILABLE' }
}

# Escape spreadsheet formulas in display text. Tracking JSON and timestamps use
# constrained formats; they are validated again before a PASS can be issued.
function ConvertTo-SafeCsvRow {
    param($Row)
    $copy = ConvertTo-ValidationRow $Row
    $tracking = [ordered]@{}
    foreach ($field in @('CheckedAtUtc','LastBootUtc','ScanRequestedAtUtc','ScanRequestBootUtc')) {
        $tracking[$field] = $copy.$field
        $copy.$field = Format-ValidationTimestamp $copy.$field
    }
    $copy.TrackingJson = ConvertTo-Json -InputObject $tracking -Compress
    foreach ($field in @('Reason','MissingUpdates','UpdateScope','RebootScope','FailedUpdates','ScopeAmbiguousUpdates','ScanRequestOutcome','ScanRequestDetails','RebootReasons','Diagnostics','Verification')) {
        if ($copy.$field -match '^\s*[=+@-]') { $copy.$field = "'" + $copy.$field }
    }
    $copy
}

function Get-ValidationColumns { (New-ValidationRow '').PSObject.Properties.Name }

# A presentation export contains only the current table view, never verification
# tracking. Escape formula-like text before opening the snapshot in a spreadsheet.
function Save-StatusCsv {
    param([string]$Path, [string[]]$Columns, [object[]]$Rows)
    $temp = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) ([IO.Path]::GetRandomFileName())
    try {
        if ($Rows.Count) {
            $Rows | ForEach-Object {
                $values = [ordered]@{}
                foreach ($column in $Columns) {
                    $value = [string]$_.$column
                    if ($value -match '^\s*[=+@-]') { $value = "'" + $value }
                    $values[$column] = $value
                }
                [pscustomobject]$values
            } | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        }
        else {
            $header = ($Columns | ForEach-Object { '"' + $_.Replace('"','""') + '"' }) -join ','
            [IO.File]::WriteAllText($temp,($header + "`r`n"),[Text.UTF8Encoding]::new($true))
        }
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,($Path + '.bak'),$true) }
        else { [IO.File]::Move($temp,$Path) }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

# Save each CSV through a same-directory temporary file. File.Replace preserves
# an existing destination atomically and creates a backup. Reports are independently
# atomic; they are NOT a cross-file transaction. Finished is saved first so a newly
# confirmed PASS exists there before it is removed from the unfinished report.
function Save-ValidationCsv {
    param([string]$Path, [object[]]$Rows)
    $folder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    $temp = Join-Path $folder ([IO.Path]::GetRandomFileName())
    try {
        if ($Rows.Count) {
            $Rows | ForEach-Object { ConvertTo-SafeCsvRow $_ } | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding UTF8
        }
        else {
            $header = ((Get-ValidationColumns | ForEach-Object { '"' + $_ + '"' }) -join ',') + "`r`n"
            [IO.File]::WriteAllText($temp, $header, [Text.UTF8Encoding]::new($true))
        }
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temp, $Path, ($Path + '.bak'), $true)
        }
        else { [IO.File]::Move($temp, $Path) }
    }
    catch { throw "Could not save '$Path': $($_.Exception.Message). Staged file, if present: $temp" }
}

function Save-WaveReports {
    param([object[]]$Rows, [hashtable]$Finished, [string]$FinishedPath, [string]$UnfinishedPath)
    foreach ($row in $Rows) {
        # A current observation supersedes an older PASS for the same DNS name.
        if ($row.Status -eq 'PASS') { $Finished[$row.ComputerName] = $row }
        else { $Finished.Remove($row.ComputerName) }
    }
    Save-ValidationCsv $FinishedPath @($Finished.Values | Sort-Object ComputerName)
    Save-ValidationCsv $UnfinishedPath @($Rows | Where-Object Status -ne 'PASS')
}
