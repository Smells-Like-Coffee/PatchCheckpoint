<#
.SYNOPSIS
    Creates local support bundles for Patch Checkpoint without querying endpoints.
.DESCRIPTION
    Captures an explicit, data-only application snapshot and selected campaign CSV
    files. A background worker writes a ZIP with collection times, file hashes and
    collection failures. Never serialize the application object, credentials,
    process memory, environment variables, or arbitrary campaign-folder contents.
#>

# Keep a bounded history of application decisions. Callers supply plain text only;
# worker/runspace/credential objects must never enter this event list.
function Add-AppDiagnosticEvent {
    param([string]$Event,[string]$Message)
    if ($script:app.DiagnosticEvents.Count -ge 2000) { $script:app.DiagnosticEvents.RemoveAt(0) }
    [void]$script:app.DiagnosticEvents.Add([pscustomobject]@{
        AtUtc = [datetime]::UtcNow.ToString('o'); Event = $Event; Message = $Message
    })
}

# Write directly to a temporary archive beside the destination; no extracted
# support folder or recursive cleanup is required. Missing files are recorded,
# so a diagnostic export remains useful when campaign storage is failing.
function Save-DiagnosticBundle {
    param([string]$Path,[string]$SnapshotJson,[object[]]$ReportFiles,[string]$SourceRoot)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $snapshot = ConvertFrom-Json -InputObject $SnapshotJson -ErrorAction Stop
    $temp = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) ([IO.Path]::GetRandomFileName())
    $archive = $null; $manifest = New-Object System.Collections.ArrayList
    function Add-DiagnosticPart {
        param([string]$Name,[byte[]]$Bytes)
        $entry = $archive.CreateEntry($Name,[IO.Compression.CompressionLevel]::Optimal)
        $stream = $entry.Open()
        try { $stream.Write($Bytes,0,$Bytes.Length) } finally { $stream.Dispose() }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
        [void]$manifest.Add([pscustomobject]@{ Entry = $Name; Bytes = $Bytes.Length; SHA256 = $hash; CollectedAtUtc = [datetime]::UtcNow.ToString('o'); Outcome = 'Included' })
    }
    function Add-DiagnosticText {
        param([string]$Name,[string]$Value)
        Add-DiagnosticPart $Name ([Text.UTF8Encoding]::new($false).GetBytes($Value))
    }
    try {
        $archive = [IO.Compression.ZipFile]::Open($temp,[IO.Compression.ZipArchiveMode]::Create)
        Add-DiagnosticText 'Snapshot.json' $SnapshotJson
        # CSV convenience copy preserves every known tracking field and exact
        # timestamps. Snapshot.json is the unformatted in-memory evidence.
        $rows = @($snapshot.Rows)
        $csv = if ($rows.Count) { @($rows | ForEach-Object { ConvertTo-SafeCsvRow $_ } | ConvertTo-Csv -NoTypeInformation) -join "`r`n" }
            else { (Get-ValidationColumns | ForEach-Object { '"' + $_ + '"' }) -join ',' }
        Add-DiagnosticText 'CurrentState.csv' ($csv + "`r`n")
        foreach ($file in $ReportFiles) {
            $stream = $null; $memory = $null
            try {
                # Names are fixed by the UI collector, never derived from CSV data.
                if ($file.Name -notin @('Finished.csv','Unfinished.csv','Finished.csv.bak','Unfinished.csv.bak')) { throw 'Unsupported diagnostic attachment.' }
                if (-not [IO.File]::Exists($file.Path)) { throw 'File is unavailable or not yet created.' }
                $stream = [IO.File]::Open($file.Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                if ($stream.Length -gt 50MB) { throw 'File exceeds the 50 MB attachment limit; use CurrentState.csv and Snapshot.json.' }
                $memory = [IO.MemoryStream]::new(); $stream.CopyTo($memory)
                if ($memory.Length -gt 50MB) { throw 'File grew beyond the attachment limit during collection.' }
                Add-DiagnosticPart ('SavedReports/' + $file.Name) $memory.ToArray()
            }
            catch {
                [void]$manifest.Add([pscustomobject]@{ Entry = ('SavedReports/' + $file.Name); CollectedAtUtc = [datetime]::UtcNow.ToString('o'); Outcome = 'Not collected'; Reason = $_.Exception.Message })
            }
            finally { if ($stream) { $stream.Dispose() }; if ($memory) { $memory.Dispose() } }
        }
        $sourceHashes = foreach ($name in @('Start-PatchCheckpoint.ps1','Validation.Core.ps1','Remote.Assessment.ps1','UI.Theme.ps1','UI.Commands.ps1','Diagnostics.Export.ps1')) {
            try {
                [pscustomobject]@{ File = $name; SHA256 = (Get-FileHash -LiteralPath (Join-Path $SourceRoot $name) -Algorithm SHA256 -ErrorAction Stop).Hash }
            }
            catch { [pscustomobject]@{ File = $name; Error = $_.Exception.Message } }
        }
        Add-DiagnosticText 'SourceHashes.json' (ConvertTo-Json -InputObject @($sourceHashes) -Depth 4)
        Add-DiagnosticText 'READ-ME.txt' @'
Patch Checkpoint diagnostic export

Snapshot.json: application/runtime settings, full in-memory campaign results,
verification evidence, selected computer, worker stages, and recent application events.
CurrentState.csv: the same campaign results in the normal tracking CSV format.
SavedReports/: finished/unfinished CSVs and available .bak files read from disk.
SourceHashes.json: hashes of known application sources; source contents are not collected.
Manifest.json: archive file hashes, collection times, and missing/failed attachments.

The in-memory snapshot is taken when export starts. Saved reports are collected
afterward and may differ if a wave is active or a checkpoint failed. Reports are
independently saved; this ZIP is not a synchronized cross-file transaction.

No new endpoint queries, scans, service changes, installation or restarts occur.
Credential objects, passwords, environment dumps, transcripts, memory dumps,
original input CSV contents, raw session JSON and unrelated files are not collected.
Settings are reconstructed from an explicit list of application fields.

This ZIP contains infrastructure identifiers, paths, patch details and diagnostics.
It is not anonymized or encrypted. Review it before sharing and use a trusted channel.
'@
        Add-DiagnosticText 'Manifest.json' (ConvertTo-Json -InputObject @($manifest) -Depth 5)
        $archive.Dispose(); $archive = $null
        # PowerShell can bind $null to an empty string for a .NET string
        # parameter. NullString explicitly requests no replacement backup file.
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    }
    finally {
        if ($archive) { $archive.Dispose() }
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

# Only explicit scalar fields and validation rows enter this snapshot. In
# particular, never pass $script:app itself to ConvertTo-Json or to a worker.
function Start-DiagnosticExport {
    param([string]$Path)
    if ($script:app.DiagnosticJob) { throw 'A diagnostic export is already running.' }
    $target = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($target) -ne '.zip') { throw 'Choose a .zip diagnostic filename.' }
    foreach ($reserved in @($script:inputPath.Box.Text,$script:finishedPath.Box.Text,$script:unfinishedPath.Box.Text,$script:app.SessionPath)) {
        if ($reserved -and $target -in @([IO.Path]::GetFullPath($reserved),([IO.Path]::GetFullPath($reserved) + '.bak'),([IO.Path]::GetFullPath($reserved) + '.lock'))) { throw 'Diagnostic export cannot overwrite campaign files.' }
    }
    if ($script:app.ExportJob -and $target -eq $script:app.ExportJob.Path) { throw 'A report export is using this filename.' }
    $allRows = @{}
    foreach ($row in $script:app.Finished.Values) { $allRows[$row.ComputerName] = $row.PSObject.Copy() }
    foreach ($row in $script:app.Rows) { $allRows[$row.ComputerName] = $row.PSObject.Copy() }
    $counts = @{}
    foreach ($row in $allRows.Values) {
        if (-not $counts.ContainsKey($row.Status)) { $counts[$row.Status] = 0 }
        $counts[$row.Status]++
    }
    $selected = if ($script:grid.SelectedRows.Count) { [string]$script:grid.SelectedRows[0].Cells['Computer'].Value } else { '' }
    Add-AppDiagnosticEvent 'Diagnostic export' 'Data-only snapshot captured; no endpoint actions requested.'
    $snapshot = [ordered]@{
        FormatVersion = 1; CapturedAtUtc = [datetime]::UtcNow.ToString('o'); AppVersion = $script:AppVersion
        Runtime = [ordered]@{
            PowerShell = $PSVersionTable.PSVersion.ToString()
            CompiledHost = $script:CompiledHost; DataRoot = $script:DataRoot
            Edition = $PSVersionTable.PSEdition; CLR = [Environment]::Version.ToString()
            OS = [Environment]::OSVersion.VersionString; Is64Bit = [Environment]::Is64BitProcess
            Apartment = [Threading.Thread]::CurrentThread.ApartmentState.ToString()
            Culture = [Globalization.CultureInfo]::CurrentCulture.Name
            TimeZone = [TimeZoneInfo]::Local.Id; Demo = [bool]$Demo
        }
        Settings = [ordered]@{
            InputPath = $script:inputPath.Box.Text; FinishedPath = $script:finishedPath.Box.Text
            UnfinishedPath = $script:unfinishedPath.Box.Text; CampaignFolder = $script:campaignFolder.Box.Text
            SessionPath = $script:app.SessionPath; Concurrency = [int]$script:concurrency.Value
            TimeoutSeconds = $TimeoutSeconds; MinimumUptimeSeconds = $MinimumUptimeSeconds
            CredentialsSet = $null -ne $script:app.Credential
        }
        Wave = [ordered]@{
            Mode = $script:app.WaveMode; Running = $script:app.Running; Stopping = $script:app.Stopping
            FatalSave = $script:app.FatalSave; RecoveryFailed = $script:app.RecoveryFailed
            CampaignStarted = $script:app.CampaignStarted; SelectedCount = $script:app.WorkIndices.Count
            Next = $script:app.Next; Done = $script:app.Done
            ElapsedSeconds = $script:app.Clock.Elapsed.TotalSeconds
            ReportsDirty = $script:app.ReportsDirty; CheckpointInProgress = $null -ne $script:app.ReportJob
            Checkpoints = $script:app.Checkpoints
            AutoVerifyDueUtc = $(if ($script:app.AutoVerifyDue) { $script:app.AutoVerifyDue.ToString('o') } else { '' })
        }
        View = [ordered]@{
            Filter = $script:filter.Text; Search = $script:search.Text; Sort = $script:binding.Sort
            SelectedComputer = $selected; Footer = $script:footer.Text; Overview = $script:campaignOverview.Text
        }
        Counts = $counts; Rows = @($allRows.Values | Sort-Object ComputerName)
        Workers = @($script:app.Workers | ForEach-Object { [pscustomobject]@{ Computer = $script:app.Rows[$_.Index].ComputerName; Slot = $_.Slot; Stage = $_.StepText; Percent = $_.StepPercent; ElapsedSeconds = $_.Clock.Elapsed.TotalSeconds; TimedOut = $_.TimedOut } })
        Staged = @($script:app.PendingDispatch | ForEach-Object { [pscustomobject]@{ Computer = $_.Original.ComputerName; Ready = $_.Ready; OriginalStatus = $_.Original.Status; ScanRequestedAtUtc = $_.Original.ScanRequestedAtUtc } })
        Events = @($script:app.DiagnosticEvents.ToArray())
    }
    $files = @()
    foreach ($pair in @(@('Finished.csv',$script:finishedPath.Box.Text),@('Unfinished.csv',$script:unfinishedPath.Box.Text))) {
        if ($pair[1]) {
            $files += [pscustomobject]@{ Name = $pair[0]; Path = [IO.Path]::GetFullPath($pair[1]) }
            $files += [pscustomobject]@{ Name = ($pair[0] + '.bak'); Path = ([IO.Path]::GetFullPath($pair[1]) + '.bak') }
        }
    }
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($Core,$Diagnostics,$Path,$Snapshot,$Files,$Root)
        $ErrorActionPreference = 'Stop'
        . ([scriptblock]::Create($Core)); . ([scriptblock]::Create($Diagnostics))
        # Serialization also belongs off the UI thread for large campaigns. The
        # snapshot contains copied rows and scalar metadata, never live controls.
        $json = ConvertTo-Json -InputObject $Snapshot -Depth 12
        Save-DiagnosticBundle $Path $json $Files $Root
    }).AddArgument($script:app.Helpers).AddArgument($script:app.DiagnosticsSource).AddArgument($target).AddArgument($snapshot).AddArgument($files).AddArgument($script:ProjectRoot)
    try {
        $script:app.DiagnosticJob = [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Path = $target }
        $script:app.DiagnosticNotice = 'Diagnostic export in progress'; $script:footer.Text = $script:app.DiagnosticNotice
        Update-AppCommandState; $script:timer.Start()
    }
    catch { $ps.Dispose(); throw }
}

function Complete-DiagnosticExport {
    $job = $script:app.DiagnosticJob
    if (-not $job -or -not $job.Handle.IsCompleted) { return }
    try {
        [void]$job.PowerShell.EndInvoke($job.Handle)
        if ($job.PowerShell.HadErrors) { throw ($job.PowerShell.Streams.Error | Out-String) }
        $script:app.DiagnosticNotice = 'Diagnostic ZIP saved: ' + $job.Path
        Add-AppDiagnosticEvent 'Diagnostic export complete' $job.Path
        $script:footer.Text = $script:app.DiagnosticNotice
    }
    catch { $script:app.DiagnosticNotice = 'Diagnostic export failed'; Show-AppError $_.Exception.Message }
    finally { $job.PowerShell.Dispose(); $script:app.DiagnosticJob = $null; Update-AppCommandState }
}

function Show-DiagnosticExportDialog {
    $dialog = [Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Diagnostic Export - contains computer names, paths and patch details; review before sharing'
    $dialog.Filter = 'Diagnostic ZIP (*.zip)|*.zip'; $dialog.DefaultExt = 'zip'
    $dialog.FileName = 'PatchCheckpoint-Diagnostics-' + [datetime]::Now.ToString('yyyyMMdd-HHmmss') + '.zip'
    if ([IO.Directory]::Exists($script:campaignFolder.Box.Text)) { $dialog.InitialDirectory = $script:campaignFolder.Box.Text }
    try { if ($dialog.ShowDialog($script:form) -eq 'OK') { Start-DiagnosticExport $dialog.FileName } }
    finally { $dialog.Dispose() }
}
