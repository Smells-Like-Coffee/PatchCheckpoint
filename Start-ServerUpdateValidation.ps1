#requires -Version 5.1
<#
.SYNOPSIS
    Opens the Server Update Validation GUI for one post-reboot assessment wave.
.DESCRIPTION
    Loads names and carried-forward verification state from a CSV. Uses a bounded
    runspace pool for Kerberos WinRM queries and saves PASS/unfinished snapshots as
    results arrive. The unfinished CSV can be reused in subsequent waves. Demo mode
    exercises the interface and reports without credentials or network operations.
.PARAMETER Demo
    Uses synthetic observations only. Always use separate demo report filenames.
.PARAMETER TimeoutSeconds
    Overall timeout per assessment. The UI remains responsive while work is running.
.PARAMETER MinimumUptimeSeconds
    Conservative startup guard; recent boots are reported NOT READY without waiting.
.EXAMPLE
    powershell.exe -NoProfile -STA -File .\Start-ServerUpdateValidation.ps1
#>
[CmdletBinding()]
param(
    [switch]$Demo,
    [ValidateRange(30,900)][int]$TimeoutSeconds = 180,
    [ValidateRange(0,1800)][int]$MinimumUptimeSeconds = 120
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or
    [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Use 64-bit Windows PowerShell 5.1 with -STA. See Launch.cmd.'
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Validation.Core.ps1')
. (Join-Path $PSScriptRoot 'UI.Theme.ps1')
$script:app = @{
    Rows = @(); Finished = @{}; Workers = (New-Object System.Collections.ArrayList)
    Credential = $null; Pool = $null; Running = $false; Stopping = $false
    Closing = $false; AllowClose = $false; BusyTick = $false; Locks = @()
    Next = 0; Done = 0; Clock = [Diagnostics.Stopwatch]::new()
    Helpers = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Validation.Core.ps1'))
    RemotePath = Join-Path $PSScriptRoot 'Remote.Assessment.ps1'
    FinishedPath = ''; UnfinishedPath = ''; FatalSave = $false; CampaignStarted = $false
    SessionPath = Join-Path $PSScriptRoot $(if ($Demo) { 'Demo-Session.json' } else { 'Validation-Session.json' })
}

# Workers have no GUI references. All remote invocation and waiting occurs away
# from the STA UI thread. No credentials are serialized to disk or command lines.
$script:workerSource = {
    param($Name,$Credential,$RemotePath,$Helpers,$Row,$Options,$DemoMode)
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($Helpers))
    if ($DemoMode) {
        [Threading.Thread]::Sleep(700)
        $r = ConvertTo-ValidationRow $Row
        $r.CheckedAtUtc = [datetime]::UtcNow.ToString('o')
        $r.LastBootUtc = [datetime]::UtcNow.AddHours(-1).ToString('o')
        $r.UptimeMinutes = '60'; $r.ClientService = 'Running'
        $r.MissingCount = '0'; $r.RebootPending = 'No'; $r.Diagnostics = 'SYNTHETIC DEMO RESULT'
        $r.UpdateScope = 'Software Center-visible SCCM updates'
        $number = 0
        [void][int]::TryParse(($Name -replace '\D',''), [ref]$number)
        switch ($number % 6) {
            1 { $r.Status = 'ACTION REQUIRED'; $r.MissingCount = '2'; $r.Reason = 'DEMO: two Software Center-visible updates waiting.'; Clear-VerificationRequest $r }
            2 { $r.Status = 'NOT READY'; $r.ClientService = 'Stopped'; $r.Reason = 'DEMO: SCCM client service stopped.' }
            3 { $r.Status = 'UNABLE TO DETERMINE'; $r.Reason = 'DEMO: remote access denied.' }
            4 { $r.Status = 'ACTION REQUIRED'; $r.RebootPending = 'Yes'; $r.RebootReasons = 'DEMO Windows servicing'; $r.Reason = 'DEMO: pending reboot.'; Clear-VerificationRequest $r }
            default {
                if ($r.ScanRequestedAtUtc) { $r.Status = 'PASS'; $r.Verification = 'DEMO CONFIRMED'; $r.Reason = 'DEMO: verification completed; checks clear.' }
                else {
                    $r.Status = 'VERIFICATION PENDING'; $r.ScanRequestedAtUtc = $r.CheckedAtUtc
                    $r.Verification = 'DEMO REQUESTED'; $r.Reason = 'DEMO: scan requested; rerun unfinished CSV to confirm.'
                }
            }
        }
        return $r
    }
    if ($Row.Verification -like 'DEMO*') { throw 'Demo tracking data cannot be used for live assessments. Use the original names-only CSV.' }
    $sessionOptions = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 60000
    Invoke-Command -ComputerName $Name -Credential $Credential -Authentication Kerberos -ConfigurationName Microsoft.PowerShell -SessionOption $sessionOptions -FilePath $RemotePath -ArgumentList $Row,$Helpers,$Options -ErrorAction Stop
}.ToString()

function Show-AppError {
    param([string]$Message)
    [void][Windows.Forms.MessageBox]::Show($script:form,$Message,'Server Update Validation','OK','Error')
}
function New-Label {
    param([string]$Text,[int]$X,[int]$Y,[int]$Width,[int]$Height = 24)
    $c = [Windows.Forms.Label]::new(); $c.Text = $Text; $c.SetBounds($X,$Y,$Width,$Height)
    $script:form.Controls.Add($c); $c
}
function New-Button {
    param([string]$Text,[int]$X,[int]$Y,[int]$Width = 100)
    $c = [ValidationUI.ActionButton]::new(); $c.Text = $Text; $c.SetBounds($X,$Y,$Width,30)
    $script:form.Controls.Add($c); $c
}
function New-PathInput {
    param([string]$Label,[int]$Y)
    $labelControl = New-Label $Label 18 ($Y + 4) 190
    $box = [Windows.Forms.TextBox]::new(); $box.SetBounds(210,$Y,700,28)
    $box.Anchor = 'Top,Left,Right'; $script:form.Controls.Add($box)
    $button = New-Button 'Browse...' 920 ($Y - 1) 95; $button.Anchor = 'Top,Right'
    [pscustomobject]@{ Label = $labelControl; Box = $box; Button = $button }
}

# Password is masked in the dialog, then retained only as PSCredential in memory.
function Set-AppCredential {
    $dialog = [Windows.Forms.Form]::new(); $dialog.Text = 'Credentials for remote assessments'
    $dialog.ClientSize = [Drawing.Size]::new(430,190); $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'; $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false
    $userLabel = [Windows.Forms.Label]::new(); $userLabel.Text = 'DOMAIN\user or user@domain'; $userLabel.SetBounds(15,12,390,22)
    $user = [Windows.Forms.TextBox]::new(); $user.SetBounds(15,37,395,25)
    $passLabel = [Windows.Forms.Label]::new(); $passLabel.Text = 'Password'; $passLabel.SetBounds(15,72,390,22)
    $pass = [Windows.Forms.TextBox]::new(); $pass.UseSystemPasswordChar = $true; $pass.SetBounds(15,97,395,25)
    $ok = [Windows.Forms.Button]::new(); $ok.Text = 'OK'; $ok.SetBounds(235,145,80,28); $ok.DialogResult = 'OK'
    $cancel = [Windows.Forms.Button]::new(); $cancel.Text = 'Cancel'; $cancel.SetBounds(325,145,85,28); $cancel.DialogResult = 'Cancel'
    $dialog.Controls.AddRange(@($userLabel,$user,$passLabel,$pass,$ok,$cancel)); $dialog.AcceptButton = $ok; $dialog.CancelButton = $cancel
    try {
        if ($dialog.ShowDialog($script:form) -ne 'OK') { return }
        if (-not $user.Text.Trim() -or -not $pass.TextLength) { throw 'Enter a username and password.' }
        $secure = [Security.SecureString]::new()
        foreach ($c in $pass.Text.ToCharArray()) { $secure.AppendChar($c) }
        $secure.MakeReadOnly()
        if ($script:app.Credential) { $script:app.Credential.Password.Dispose() }
        $script:app.Credential = [pscredential]::new($user.Text.Trim(),$secure)
        $script:accountLabel.Text = 'Account: ' + $script:app.Credential.UserName
    }
    finally { $pass.Clear(); $dialog.Dispose() }
}

function Update-GridRow {
    param([int]$Index)
    $r = $script:app.Rows[$Index]; $d = $script:table.Rows[$Index]
    $d['Computer'] = $r.ComputerName; $d['Status'] = $r.Status; $d['Reason / current step'] = $r.Reason
    $d['Missing'] = [string]$r.MissingCount; $d['Reboot'] = $r.RebootPending; $d['Last checked (UTC)'] = Format-ValidationTimestamp $r.CheckedAtUtc
    if ($script:grid.SelectedRows.Count -and [string]$script:grid.SelectedRows[0].Cells['Computer'].Value -eq $r.ComputerName) {
        $script:detail.Text = Format-ValidationDetails $r
    }
}
function Load-AppRows {
    # The original inventory is read only before the campaign starts. Subsequent
    # waves load the durable unfinished report, preserving exact scan boundaries.
    if ($script:app.CampaignStarted) {
        $items = @(Import-Csv -LiteralPath $script:app.UnfinishedPath -ErrorAction Stop)
        if ($items.Count) { $script:app.Rows = @(Read-ValidationInput $script:app.UnfinishedPath) }
        else {
            $header = [IO.File]::ReadLines($script:app.UnfinishedPath) | Select-Object -First 1
            if ($header -notlike '*"TrackingJson"*' -or $header -notlike '*"ComputerName"*') { throw 'Unfinished report header is invalid.' }
            $script:app.Rows = @()
        }
    }
    else { $script:app.Rows = @(Read-ValidationInput $script:inputPath.Box.Text) }
    $script:table.Clear()
    foreach ($row in $script:app.Rows) {
        $row.Status = 'QUEUED'; $row.Reason = 'Waiting for a worker'
        [void]$script:table.Rows.Add($row.ComputerName,$row.Status,$row.Reason,[string]$row.MissingCount,$row.RebootPending,(Format-ValidationTimestamp $row.CheckedAtUtc))
    }
    # Finished computers remain viewable but are never queued in later waves.
    foreach ($row in @($script:app.Finished.Values | Sort-Object ComputerName)) {
        if ($row.ComputerName -notin @($script:app.Rows | ForEach-Object { $_.ComputerName })) {
            [void]$script:table.Rows.Add($row.ComputerName,$row.Status,$row.Reason,[string]$row.MissingCount,$row.RebootPending,(Format-ValidationTimestamp $row.CheckedAtUtc))
        }
    }
    $script:footer.Text = "Loaded $($script:app.Rows.Count) computers. No server actions started."
}

# Persist paths and concurrency only. Credentials are deliberately memory-only.
# Atomic replacement avoids leaving partial restart settings after interruption.
function Save-AppSession {
    $session = [ordered]@{ Version = 1; InputPath = $script:inputPath.Box.Text; FinishedPath = $script:app.FinishedPath; UnfinishedPath = $script:app.UnfinishedPath; Concurrency = [int]$script:concurrency.Value }
    $temp = $script:app.SessionPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $session))
        if ([IO.File]::Exists($script:app.SessionPath)) { [IO.File]::Replace($temp,$script:app.SessionPath,($script:app.SessionPath + '.bak'),$true) }
        else { [IO.File]::Move($temp,$script:app.SessionPath) }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Reset-AppCampaign {
    if ($script:app.Running) { return }
    # Explicit local reset: reports are preserved. Use new output paths for a new
    # maintenance campaign if the previous finished report should stay separate.
    if ([IO.File]::Exists($script:app.SessionPath)) { [IO.File]::Delete($script:app.SessionPath) }
    if ([IO.File]::Exists($script:app.SessionPath + '.bak')) { [IO.File]::Delete($script:app.SessionPath + '.bak') }
    $script:app.CampaignStarted = $false; $script:app.Rows = @(); $script:app.Finished = @{}
    $script:table.Clear(); $script:detail.Clear()
    $script:startButton.Text = 'Start wave'; $script:loadButton.Text = 'Load list'
    Set-SetupEnabled $true
    $script:footer.Text = 'New list: select input and report paths. Previous reports are preserved.'
}
function Update-AppProgress {
    $running = $script:app.Workers.Count
    $queued = $script:app.Rows.Count - $script:app.Next
    $total = $script:app.Rows.Count
    $script:progress.Maximum = [math]::Max(1,$total); $script:progress.Value = $script:app.Done
    $script:summary.Text = "$total in wave | $($script:app.Done) checked | $running active | $queued queued"
    $counts = foreach ($status in @('PASS','VERIFICATION PENDING','ACTION REQUIRED','NOT READY','UNABLE TO DETERMINE')) {
        $count = if ($status -eq 'PASS') { $script:app.Finished.Count } else { @($script:app.Rows | Where-Object Status -eq $status).Count }
        '{0} {1}' -f $count,$status
    }
    $script:counts.Text = $counts -join '    '
    $script:footer.Text = 'Elapsed {0} | {1} | Reports saved after each assessment' -f $script:app.Clock.Elapsed.ToString('hh\:mm\:ss'), $(if ($Demo) { 'DEMO: no network actions' } else { 'Read-only except verification scan' })
    Update-ValidationThemeSummary
}
function Save-AppReports {
    Save-WaveReports -Rows $script:app.Rows -Finished $script:app.Finished -FinishedPath $script:app.FinishedPath -UnfinishedPath $script:app.UnfinishedPath
}
function Set-SetupEnabled {
    param([bool]$Enabled)
    foreach ($control in @($script:inputPath.Box,$script:inputPath.Button,$script:finishedPath.Box,$script:finishedPath.Button,$script:unfinishedPath.Box,$script:unfinishedPath.Button,$script:credentialButton,$script:concurrency,$script:startButton,$script:loadButton)) { $control.Enabled = $Enabled }
    $script:stopButton.Enabled = -not $Enabled
    if ($script:app.CampaignStarted) {
        foreach ($pathControl in @($script:inputPath,$script:finishedPath,$script:unfinishedPath)) { $pathControl.Box.Enabled = $false; $pathControl.Button.Enabled = $false }
        $script:startButton.Text = 'Run next wave'; $script:loadButton.Text = 'New list'
    }
    if ($Demo) { $script:credentialButton.Enabled = $false }
}
function Release-AppResources {
    if ($script:app.Pool) { $script:app.Pool.Close(); $script:app.Pool.Dispose(); $script:app.Pool = $null }
    foreach ($stream in $script:app.Locks) { $stream.Dispose() }; $script:app.Locks = @()
}

function Start-AppWave {
    if ($script:app.Running) { return }
    if (-not $Demo -and -not $script:app.Credential) { throw 'Set remote credentials before starting.' }
    Load-AppRows
    if ($script:app.CampaignStarted -and -not $script:app.Rows.Count) {
        $script:footer.Text = 'Campaign complete. All computers have passed; no server actions started.'
        return
    }
    $input = [IO.Path]::GetFullPath($script:inputPath.Box.Text)
    $finished = [IO.Path]::GetFullPath($script:finishedPath.Box.Text)
    $unfinished = [IO.Path]::GetFullPath($script:unfinishedPath.Box.Text)
    if ($finished -eq $unfinished -or $input -eq $finished) { throw 'Finished output must differ from both input and unfinished output.' }
    foreach ($path in @($finished,$unfinished)) {
        if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($path))) { throw "Output folder does not exist: $path" }
        if ([IO.Path]::GetExtension($path) -ne '.csv') { throw 'Both report filenames must end in .csv.' }
    }
    # Starting a wave updates the selected report files without an overwrite prompt.
    # PASS accumulation, unfinished tracking, and automatic backups remain active.
    $script:app.FinishedPath = $finished; $script:app.UnfinishedPath = $unfinished; $script:app.Finished = @{}
    try {
        # Lock files are deliberately retained. Deleting a lock after release could
        # race a second process. Open handles, not file existence, enforce the lock.
        foreach ($path in @($finished,$unfinished) | Sort-Object) {
            $stream = [IO.File]::Open(($path + '.lock'),'OpenOrCreate','ReadWrite','None')
            $script:app.Locks += $stream
        }
        if ([IO.File]::Exists($finished)) {
            foreach ($old in @(Import-Csv -LiteralPath $finished)) {
                if ($old.Status -ne 'PASS' -or $old.SchemaVersion -notin @('1','2','3','4')) { throw 'Existing finished CSV is not a compatible PASS report. Choose a new file.' }
                $script:app.Finished[$old.ComputerName] = ConvertTo-ValidationRow $old
            }
        }
        Save-AppReports
        Save-AppSession
        $script:app.CampaignStarted = $true
        $script:app.Pool = [RunspaceFactory]::CreateRunspacePool(1,[int]$script:concurrency.Value)
        $script:app.Pool.ApartmentState = 'MTA'; $script:app.Pool.Open()
        $script:app.Next = 0; $script:app.Done = 0; $script:app.Stopping = $false; $script:app.FatalSave = $false
        $script:app.Running = $true; $script:app.Clock.Restart(); Set-SetupEnabled $false
        $script:timer.Start()
    }
    catch { Release-AppResources; throw }
}

# Timer ticks run on the UI thread; workers return data only. No DoEvents-based
# polling loops or worker updates to WinForms controls are necessary.
function Invoke-AppTick {
    if ($script:app.BusyTick -or -not $script:app.Running) { return }
    $script:app.BusyTick = $true
    try {
        foreach ($work in $script:app.Workers.ToArray()) {
            if (-not $work.Handle.IsCompleted -and $work.Clock.Elapsed.TotalSeconds -ge $TimeoutSeconds -and -not $work.TimedOut) {
                $work.TimedOut = $true
                $work.StopHandle = $work.PowerShell.BeginStop($null,$null)
            }
            if (-not $work.Handle.IsCompleted) { continue }
            $row = ConvertTo-ValidationRow $script:app.Rows[$work.Index]
            try {
                $result = @($work.PowerShell.EndInvoke($work.Handle))
                if ($work.TimedOut) { throw "Assessment exceeded $TimeoutSeconds seconds. Scan submission may be uncertain; review tracking and client logs." }
                if ($work.PowerShell.HadErrors -or $result.Count -ne 1) {
                    throw "Remote assessment failed: $($work.PowerShell.Streams.Error | Out-String)"
                }
                $row = ConvertTo-ValidationRow $result[0]
                if ($row.ComputerName -ne $script:app.Rows[$work.Index].ComputerName -or $row.Status -notin @('PASS','VERIFICATION PENDING','ACTION REQUIRED','NOT READY','UNABLE TO DETERMINE')) { throw 'Worker returned an invalid result.' }
            }
            catch { $row.Status = 'UNABLE TO DETERMINE'; $row.Reason = $_.Exception.Message; $row.CheckedAtUtc = [datetime]::UtcNow.ToString('o') }
            finally {
                if ($work.StopHandle) { $work.PowerShell.EndStop($work.StopHandle) }
                $work.PowerShell.Dispose(); $work.Clock.Stop(); $script:app.Workers.Remove($work)
            }
            $script:app.Rows[$work.Index] = $row; $script:app.Done++
            Update-GridRow $work.Index
            Save-AppReports
        }
        while (-not $script:app.Stopping -and $script:app.Next -lt $script:app.Rows.Count -and $script:app.Workers.Count -lt [int]$script:concurrency.Value) {
            $index = $script:app.Next; $original = ConvertTo-ValidationRow $script:app.Rows[$index]
            $script:app.Rows[$index].Status = 'CHECKING'; $script:app.Rows[$index].Reason = 'Assessing readiness, updates, reboot and scan evidence'
            # Durable intent precedes remote dispatch. If the process is terminated
            # after a scan is submitted but before its response, never silently
            # submit another scan or claim PASS on the following run.
            if (-not $script:app.Rows[$index].ScanRequestedAtUtc) { $script:app.Rows[$index].Verification = 'ATTEMPT IN PROGRESS' }
            Save-AppReports
            $ps = [PowerShell]::Create(); $ps.RunspacePool = $script:app.Pool
            [void]$ps.AddScript($script:workerSource).AddArgument($original.ComputerName).AddArgument($script:app.Credential).AddArgument($script:app.RemotePath).AddArgument($script:app.Helpers).AddArgument($original).AddArgument(@{ MinimumUptimeSeconds = $MinimumUptimeSeconds }).AddArgument([bool]$Demo)
            try { $handle = $ps.BeginInvoke() }
            catch { $ps.Dispose(); throw }
            [void]$script:app.Workers.Add([pscustomobject]@{ Index = $index; PowerShell = $ps; Handle = $handle; Clock = [Diagnostics.Stopwatch]::StartNew(); TimedOut = $false; StopHandle = $null })
            $script:app.Next++; Update-GridRow $index
        }
        Update-AppProgress
        if (($script:app.Next -eq $script:app.Rows.Count -or $script:app.Stopping) -and -not $script:app.Workers.Count) {
            Save-AppReports; $script:timer.Stop(); $script:app.Clock.Stop(); $script:app.Running = $false
            Release-AppResources; Set-SetupEnabled $true
            $script:footer.Text += " | $($script:app.Finished.Count) finished; $(@($script:app.Rows | Where-Object Status -ne 'PASS').Count) remaining. Run next wave to continue."
            if ($script:app.Closing) { $script:app.AllowClose = $true; $script:form.Close() }
        }
    }
    catch {
        # Fail closed on a save error. Leave existing checkpoints, stop dispatching,
        # and allow active workers to finish; expose the error instead of hiding it.
        $script:app.Stopping = $true
        if (-not $script:app.FatalSave) { $script:app.FatalSave = $true; Show-AppError ($_.Exception.Message + "`r`nDispatch stopped. Active checks will finish. Resolve the output problem before closing.") }
        $script:footer.Text = 'ERROR: report save or processing failed. New dispatch stopped; check output permissions and disk space.'
    }
    finally { $script:app.BusyTick = $false }
}

# Build a resizable, keyboard-accessible desktop layout using only built-in .NET.
$script:form = [Windows.Forms.Form]::new()
$script:form.Text = 'Server Update Validation 1.0.6' + $(if ($Demo) { ' [OFFLINE DEMO]' } else { '' })
$script:form.ClientSize = [Drawing.Size]::new(1040,750); $script:form.MinimumSize = [Drawing.Size]::new(1056,789)
$script:form.StartPosition = 'CenterScreen'; $script:form.Font = [Drawing.Font]::new('Segoe UI',10)
$script:form.BackColor = [Drawing.Color]::FromArgb(247,249,252)
$title = New-Label 'Server Update Validation' 18 12 700 35; $title.Font = [Drawing.Font]::new('Segoe UI',18,[Drawing.FontStyle]::Bold)
$script:inputPath = New-PathInput 'Input CSV' 60
$script:finishedPath = New-PathInput 'Finished CSV (PASS only)' 98
$script:unfinishedPath = New-PathInput 'Unfinished CSV / next wave' 136
$script:credentialButton = New-Button 'Set credentials...' 18 178 150
$script:accountLabel = New-Label 'Account: not set' 180 183 380
[void](New-Label 'Concurrent checks' 580 183 145)
$script:concurrency = [Windows.Forms.NumericUpDown]::new(); $script:concurrency.SetBounds(728,180,65,28)
$script:concurrency.Minimum = 1; $script:concurrency.Maximum = 32; $script:concurrency.Value = 8; $script:form.Controls.Add($script:concurrency)
$script:loadButton = New-Button 'Load list' 18 218 110
$script:startButton = New-Button 'Start wave' 140 218 120
$script:startButton.BackColor = [Drawing.Color]::FromArgb(0,105,190); $script:startButton.ForeColor = [Drawing.Color]::White
$script:stopButton = New-Button 'Stop after active checks' 272 218 205; $script:stopButton.Enabled = $false
$script:summary = New-Label 'Load an input CSV to begin.' 18 265 990
$script:summary.Anchor = 'Top,Left,Right'
$script:progress = [ValidationUI.BlueProgress]::new(); $script:progress.SetBounds(18,294,997,20); $script:progress.Anchor = 'Top,Left,Right'; $script:form.Controls.Add($script:progress)
$script:counts = New-Label '' 18 323 1000 28; $script:counts.Font = [Drawing.Font]::new('Segoe UI',9)
[void](New-Label 'Computer status' 18 359 180)
$script:filter = [Windows.Forms.ComboBox]::new(); $script:filter.SetBounds(200,354,240,28); $script:filter.DropDownStyle = 'DropDownList'
[void]$script:filter.Items.AddRange(@('All','Unfinished','PASS','VERIFICATION PENDING','ACTION REQUIRED','NOT READY','UNABLE TO DETERMINE')); $script:filter.SelectedIndex = 0; $script:form.Controls.Add($script:filter)
[void](New-Label 'Search computer' 460 359 145)
$script:search = [Windows.Forms.TextBox]::new(); $script:search.SetBounds(610,354,405,28); $script:search.Anchor = 'Top,Left,Right'; $script:form.Controls.Add($script:search)
$script:table = [Data.DataTable]::new()
foreach ($name in @('Computer','Status','Reason / current step','Missing','Reboot','Last checked (UTC)')) { [void]$script:table.Columns.Add($name,[string]) }
$script:binding = [Windows.Forms.BindingSource]::new(); $script:binding.DataSource = $script:table
$script:grid = [ValidationUI.StatusGrid]::new(); $script:grid.SetBounds(18,394,997,213)
$script:grid.Anchor = 'Top,Bottom,Left,Right'; $script:grid.DataSource = $script:binding
$script:grid.ReadOnly = $true; $script:grid.AllowUserToAddRows = $false; $script:grid.AllowUserToDeleteRows = $false
$script:grid.MultiSelect = $false; $script:grid.SelectionMode = 'FullRowSelect'; $script:grid.RowHeadersVisible = $false
$script:grid.AutoSizeColumnsMode = 'Fill'; $script:grid.BackgroundColor = [Drawing.Color]::White; $script:grid.ScrollBars = 'Both'
$script:form.Controls.Add($script:grid)
$script:grid.Add_DataBindingComplete({
    if ($script:grid.Columns.Count -eq 6) {
        $script:grid.Columns['Computer'].FillWeight = 18
        $script:grid.Columns['Status'].FillWeight = 26
        $script:grid.Columns['Reason / current step'].FillWeight = 45
        $script:grid.Columns['Missing'].FillWeight = 10
        $script:grid.Columns['Missing'].MinimumWidth = 95
        $script:grid.Columns['Missing'].HeaderText = 'Updates'
        $script:grid.Columns['Reboot'].FillWeight = 10
        $script:grid.Columns['Last checked (UTC)'].FillWeight = 26
    }
})
$script:detail = [Windows.Forms.TextBox]::new(); $script:detail.SetBounds(18,620,997,87); $script:detail.Anchor = 'Bottom,Left,Right'
$script:detail.Multiline = $true; $script:detail.ReadOnly = $true; $script:detail.ScrollBars = 'Vertical'; $script:form.Controls.Add($script:detail)
$script:footer = New-Label 'Ready. No server actions started.' 18 720 1000; $script:footer.Anchor = 'Bottom,Left,Right'; $script:footer.Font = [Drawing.Font]::new('Segoe UI',9)

# The input dialog never overwrites files; output dialogs select filenames. The
# reports are updated automatically when a wave starts; backups are automatic.
$script:inputPath.Button.Add_Click({
    $d = [Windows.Forms.OpenFileDialog]::new(); $d.Filter = 'CSV files (*.csv)|*.csv'
    try { if ($d.ShowDialog($script:form) -eq 'OK') { $script:inputPath.Box.Text = $d.FileName; Load-AppRows } }
    catch { Show-AppError $_.Exception.Message } finally { $d.Dispose() }
})
$script:finishedPath.Button.Add_Click({
    $d = [Windows.Forms.SaveFileDialog]::new(); $d.Filter = 'CSV files (*.csv)|*.csv'; $d.DefaultExt = 'csv'; $d.OverwritePrompt = $false
    try { if ($d.ShowDialog($script:form) -eq 'OK') { $script:finishedPath.Box.Text = $d.FileName } } finally { $d.Dispose() }
})
$script:unfinishedPath.Button.Add_Click({
    $d = [Windows.Forms.SaveFileDialog]::new(); $d.Filter = 'CSV files (*.csv)|*.csv'; $d.DefaultExt = 'csv'; $d.OverwritePrompt = $false
    try { if ($d.ShowDialog($script:form) -eq 'OK') { $script:unfinishedPath.Box.Text = $d.FileName } } finally { $d.Dispose() }
})
$script:credentialButton.Add_Click({ try { Set-AppCredential } catch { Show-AppError $_.Exception.Message } })
$script:loadButton.Add_Click({ try { if ($script:loadButton.Text -eq 'New list') { Reset-AppCampaign } else { Load-AppRows } } catch { Show-AppError $_.Exception.Message } })
$script:startButton.Add_Click({ try { Start-AppWave } catch { Show-AppError $_.Exception.Message } })
$script:stopButton.Add_Click({ $script:app.Stopping = $true; $script:stopButton.Enabled = $false })
$script:grid.Add_SelectionChanged({
    if ($script:grid.SelectedRows.Count) {
        $name = [string]$script:grid.SelectedRows[0].Cells['Computer'].Value
        $r = @($script:app.Rows | Where-Object ComputerName -eq $name)
        if (-not $r.Count -and $script:app.Finished.ContainsKey($name)) { $r = @($script:app.Finished[$name]) }
        if ($r.Count -eq 1) { $script:detail.Text = Format-ValidationDetails $r[0] }
    }
})
$script:grid.Add_CellFormatting({
    param($sender,$eventArgs)
    if ($eventArgs.ColumnIndex -ge 0 -and $sender.Columns[$eventArgs.ColumnIndex].Name -eq 'Status') {
        $color = switch ([string]$eventArgs.Value) {
            'PASS' { [Drawing.Color]::DarkGreen }; 'ACTION REQUIRED' { [Drawing.Color]::Firebrick }
            'VERIFICATION PENDING' { [Drawing.Color]::DarkGoldenrod }; 'CHECKING' { [Drawing.Color]::RoyalBlue }
            default { [Drawing.Color]::DimGray }
        }
        $eventArgs.CellStyle.ForeColor = $color
    }
})
$applyFilter = {
    $parts = New-Object 'System.Collections.Generic.List[string]'
    if ($script:filter.Text -eq 'Unfinished') { $parts.Add("Status <> 'PASS'") }
    elseif ($script:filter.Text -ne 'All') { $parts.Add("Status = '$($script:filter.Text)'") }
    if ($script:search.Text) {
        # DataView expressions have their own escaping, independent of PowerShell.
        $s = $script:search.Text.Replace("'","''").Replace('[','[[]').Replace('%','[%]').Replace('*','[*]')
        $parts.Add("Computer LIKE '%$s%'")
    }
    try { $script:binding.Filter = $parts -join ' AND ' } catch { $script:footer.Text = 'Search contains an unsupported filter character.' }
}
$script:filter.Add_SelectedIndexChanged($applyFilter); $script:search.Add_TextChanged($applyFilter)
$script:timer = [Windows.Forms.Timer]::new(); $script:timer.Interval = 150; $script:timer.Add_Tick({ Invoke-AppTick })
$script:form.Add_FormClosing({
    param($sender,$eventArgs)
    if ($script:app.Running -and -not $script:app.AllowClose) {
        $eventArgs.Cancel = $true
        if ([Windows.Forms.MessageBox]::Show($script:form,'Stop after active checks, save reports, then close?','Active wave','YesNo','Question') -eq 'Yes') {
            $script:app.Stopping = $true; $script:app.Closing = $true
        }
    }
})
# Expand after anchors are established so the initial view has room for status
# explanations while remaining usable on smaller displays at the minimum size.
$script:form.ClientSize = [Drawing.Size]::new(1200,850)
Set-ValidationTheme
if ($Demo) {
    $script:credentialButton.Enabled = $false; $script:accountLabel.Text = 'OFFLINE DEMO - no credentials or server actions'
    $script:inputPath.Box.Text = Join-Path $PSScriptRoot 'Computers.example.csv'
    $script:finishedPath.Box.Text = Join-Path $PSScriptRoot 'Demo-Finished.csv'
    $script:unfinishedPath.Box.Text = Join-Path $PSScriptRoot 'Demo-Unfinished.csv'
    Load-AppRows
}
# Resume local campaign settings without storing credentials or triggering work.
function Restore-AppSession {
    if (-not [IO.File]::Exists($script:app.SessionPath)) { return }
    try {
        $saved = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:app.SessionPath)) -ErrorAction Stop
        if ($saved.Version -ne 1 -or $saved.Concurrency -lt 1 -or $saved.Concurrency -gt 32) { throw 'Invalid session settings.' }
        foreach ($reportPath in @($saved.FinishedPath,$saved.UnfinishedPath)) {
            if (-not [IO.File]::Exists($reportPath) -or [IO.Path]::GetExtension($reportPath) -ne '.csv') { throw 'Saved report is missing or invalid.' }
        }
        $script:inputPath.Box.Text = $saved.InputPath
        $script:finishedPath.Box.Text = $saved.FinishedPath; $script:app.FinishedPath = $saved.FinishedPath
        $script:unfinishedPath.Box.Text = $saved.UnfinishedPath; $script:app.UnfinishedPath = $saved.UnfinishedPath
        $script:concurrency.Value = $saved.Concurrency
        foreach ($old in @(Import-Csv -LiteralPath $saved.FinishedPath)) {
            if ($old.Status -ne 'PASS') { throw 'Saved finished report contains a non-PASS row.' }
            $script:app.Finished[$old.ComputerName] = ConvertTo-ValidationRow $old
        }
        $script:app.CampaignStarted = $true
        Load-AppRows; Set-SetupEnabled $true
        $script:footer.Text = 'Campaign restored. Set credentials, then run the next wave. No server actions started.'
    }
    catch {
        $script:app.CampaignStarted = $false; $script:app.Finished = @{}
        $script:footer.Text = 'Saved campaign could not be restored: ' + $_.Exception.Message
        $script:startButton.Enabled = $false; $script:loadButton.Text = 'New list'
    }
}
Restore-AppSession
try { [Windows.Forms.Application]::Run($script:form) }
finally {
    $script:timer.Stop(); $script:timer.Dispose()
    foreach ($work in $script:app.Workers.ToArray()) { $work.PowerShell.Stop(); $work.PowerShell.Dispose() }
    Release-AppResources
    if ($script:app.Credential) { $script:app.Credential.Password.Dispose() }
    $script:binding.Dispose(); $script:table.Dispose(); $script:form.Dispose()
    $script:statusFont.Dispose()
}
