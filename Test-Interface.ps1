#requires -Version 5.1
<#
.SYNOPSIS
    Exercises two demo waves and graceful stop using the actual GUI and runspace pool.
.DESCRIPTION
    Runs synthetic workers only. Saves reports and a rendered preview under a new
    UI-Test-* folder beside this script. No remote credentials or network calls.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$testRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:testFolder = Join-Path $testRoot ('UI-Test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:testFolder)
function Wait-DemoWave {
    $deadline = [datetime]::UtcNow.AddSeconds(60)
    while ($script:app.Running -and [datetime]::UtcNow -lt $deadline) {
        Invoke-AppTick
        [Windows.Forms.Application]::DoEvents()
        [Threading.Thread]::Sleep(50)
        if ($script:app.Workers.Count -gt 2) { throw 'Concurrency exceeded requested limit.' }
    }
    if ($script:app.Running -or $script:app.FatalSave) { throw 'Demo wave failed to complete.' }
}
function Wait-StatusExport {
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    while ($script:app.ExportJob -and [datetime]::UtcNow -lt $deadline) {
        Invoke-AppTick; [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(25)
    }
    if ($script:app.ExportJob -or $script:app.ExportNotice -eq 'Export failed') { throw 'Status export failed to finish.' }
}
function Invoke-InterfaceSmoke {
    $script:app.SessionPath = Join-Path $script:testFolder 'Test-Session.json'
    $script:finishedPath.Box.Text = Join-Path $script:testFolder 'Finished.csv'
    $script:unfinishedPath.Box.Text = Join-Path $script:testFolder 'Unfinished.csv'
    $script:concurrency.Value = 2
    $script:form.Show()
    if ($script:AppVersion -notlike '0.*beta*') { throw 'Application version must identify a pre-1.0 beta.' }
    if ($script:startButton.Parent -ne $script:checksCard -or $script:inputPath.Box.Parent -ne $script:setupCard -or $script:checksCard -eq $script:setupCard) { throw 'Setup and check actions must use separate panes.' }
    $expandedHeight = $script:grid.Height
    Invoke-AppCommand 'Setup'
    if ($script:setupCard.Height -ne 44 -or $script:inputPath.Box.Visible -or -not $script:startButton.Visible -or $script:grid.Height -le $expandedHeight -or $script:menuItems['Setup'].Checked) { throw 'Collapsing setup must preserve check actions and reclaim table space.' }
    Invoke-AppCommand 'Setup'
    Invoke-AppCommand 'WorkerProgress'
    if ($script:workerFlow.Visible -or $script:menuItems['WorkerProgress'].Checked) { throw 'View must be able to hide individual check progress.' }
    Invoke-AppCommand 'WorkerProgress'
    if (-not $script:workerFlow.Visible) { throw 'View must restore individual check progress.' }
    foreach ($control in @($script:inputPath.Box,$script:concurrency,$script:startButton,$script:setupToggle,$script:filter,$script:search,$script:exportButton)) {
        if (-not $script:toolTips.GetToolTip($control)) { throw 'An operator control has no explanatory tooltip.' }
    }
    foreach ($status in $script:statusCountLabels.Keys) {
        $label = $script:statusCountLabels[$status]
        $method = $label.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'NonPublic,Instance')
        [void]$method.Invoke($label,@([EventArgs]::Empty))
        if ($script:filter.Text -ne $status -or -not $script:filterMenuItems[$status].Checked) { throw 'Status summary click did not synchronize the table and View menu filter.' }
    }
    Reset-AppView
    Write-Output 'PASS: beta version, separate/collapsible setup, clickable status summaries, tooltips, and worker-view toggle'
    if (($script:menu.Items | ForEach-Object Text) -join '|' -ne '&File|&Actions|&View|&Help') { throw 'Native menu structure is incomplete.' }
    if ($script:menuItems['Export'].ShortcutKeys -ne [Windows.Forms.Keys]'Control,E' -or $script:menuItems['Guide'].ShortcutKeys -ne [Windows.Forms.Keys]::F1) { throw 'Menu shortcuts are missing.' }
    if ($script:rowMenu.Items.Count -ne 3 -or -not $script:menuItems['Initial'].Enabled -or $script:menuItems['Verify'].Enabled) { throw 'Initial command state or row-copy menu is incorrect.' }
    foreach ($topic in @('Guide','Troubleshooting','ReleaseNotes','About')) {
        if ((Get-AppHelpText $topic).Length -lt 100) { throw "Missing help content: $topic" }
    }
    $gridHeight = $script:grid.Height
    Invoke-AppCommand 'Details'
    if ($script:detail.Visible -or $script:grid.Height -le $gridHeight -or $script:menuItems['Details'].Checked) { throw 'Hiding details must expand the status table and update the menu checkmark.' }
    Invoke-AppCommand 'Details'
    if (-not $script:detail.Visible -or $script:grid.Height -ne $gridHeight) { throw 'Restoring details did not restore the layout.' }
    Write-Output 'PASS: native menus, shortcuts, local help, command availability, and details toggle'
    if ($script:filter.Text -ne 'Unfinished' -or $script:binding.Filter -ne "Status <> 'PASS'") { throw 'Unfinished must be the active default view.' }
    # Deliberately slow only the background writer. A separate GUI timer must
    # keep ticking while saves run, and no remote worker may bypass its checkpoint.
    $script:app.Helpers += "`r`nfunction Save-TestWaveReports {`r`n" + (Get-Command Save-WaveReports).Definition + "`r`n}`r`nfunction Save-WaveReports { param(`$Rows,`$Finished,`$FinishedPath,`$UnfinishedPath) [Threading.Thread]::Sleep(250); Save-TestWaveReports `$Rows `$Finished `$FinishedPath `$UnfinishedPath }"
    $script:heartbeatCount = 0
    $script:heartbeat = [Windows.Forms.Timer]::new(); $script:heartbeat.Interval = 50
    $script:heartbeat.Add_Tick({ $script:heartbeatCount++ }); $script:heartbeat.Start()
    if ($script:startButton.GetType().FullName -ne 'ValidationUI.ActionButton' -or -not $script:startButton.Primary) { throw 'Primary action theme is missing.' }
    if ($script:progress.GetType().FullName -ne 'ValidationUI.BlueProgress') { throw 'Blue progress theme is missing.' }
    if ($script:grid.Parent -ne $script:resultsCard -or $script:inputPath.Box.Parent -ne $script:setupCard) { throw 'Card grouping is missing.' }
    $savedSize = $script:form.Size
    $script:form.Size = $script:form.MinimumSize
    [Windows.Forms.Application]::DoEvents()
    if ($script:grid.Height -lt 90 -or $script:stopButton.Right -gt $script:setupCard.ClientSize.Width -or $script:detail.Bottom -gt $script:resultsCard.ClientSize.Height) { throw 'Minimum-size layout clips a required control.' }
    $script:form.Size = $savedSize
    [Windows.Forms.Application]::DoEvents()
    Write-Output 'PASS: themed controls, card grouping, and minimum-window layout'
    $script:menuItems['Initial'].PerformClick()
    Invoke-AppTick
    if ($script:menuItems['New'].Enabled -or $script:menuItems['Resume'].Enabled -or $script:menuItems['Verify'].Enabled -or -not $script:menuItems['Export'].Enabled) { throw 'Busy command state allows conflicting campaign operations.' }
    if (-not $script:app.ReportJob -or $script:app.Workers.Count -ne 0) { throw 'Dispatch must wait for its background checkpoint.' }
    $deadline = [datetime]::UtcNow.AddSeconds(12)
    while (-not @($script:app.Workers | Where-Object { $_.StepPercent -ge 10 }).Count -and [datetime]::UtcNow -lt $deadline) {
        Invoke-AppTick; [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(25)
    }
    $activeProgress = @($script:app.Workers | Where-Object { $_.StepPercent -ge 10 })
    if (-not $activeProgress.Count -or $script:workerSlots[$activeProgress[0].Slot].Bar.Style -ne 'Continuous') { throw 'Individual bars must reflect actual pipeline progress records.' }
    if (@($script:workerSlots.Values | Where-Object { $_.Panel.Visible }).Count -ne 2) { throw 'Individual progress slots must match configured concurrency.' }
    Write-Output 'PASS: individual worker bars consume observed progress records and match concurrency'
    # Render the real controls, not a generated UI mockup.
    [Windows.Forms.Application]::DoEvents()
    $bitmap = [Drawing.Bitmap]::new($script:form.Width,$script:form.Height)
    try { $script:form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height)); $bitmap.Save((Join-Path $script:testFolder 'GUI-preview.png')) }
    finally { $bitmap.Dispose() }
    Wait-DemoWave
    $bitmap = [Drawing.Bitmap]::new($script:form.Width,$script:form.Height)
    try { $script:form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height)); $bitmap.Save((Join-Path $script:testFolder 'GUI-preview.png')) }
    finally { $bitmap.Dispose() }
    if (@(Import-Csv -LiteralPath $script:app.UnfinishedPath).Count -ne 12) { throw 'First wave must retain all computers.' }
    if (@($script:app.Rows | Where-Object Status -eq 'VERIFICATION PENDING').Count -ne 4) { throw 'First wave did not request four synthetic scans.' }
    Write-Output 'PASS: actual GUI, runspace concurrency, first-wave reports'
    Invoke-AppCommand 'WorkerProgress'
    $savedView = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:app.SessionPath))
    if ($savedView.ShowWorkerProgress -ne $false) { throw 'Worker-bar preference must be saved when idle.' }
    Restore-AppSession
    if ($script:app.ShowWorkerProgress -or $script:menuItems['WorkerProgress'].Checked -or $script:workerFlow.Visible) { throw 'Saved worker-bar preference must survive campaign restore.' }
    Invoke-AppCommand 'WorkerProgress'
    Invoke-AppCommand 'Setup'
    $savedView = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:app.SessionPath))
    if (-not $savedView.SetupCollapsed) { throw 'Collapsed setup preference must be saved.' }
    Invoke-AppCommand 'Setup'
    Write-Output 'PASS: view preferences persist without changing campaign results'
    $copyName = Get-AppCopyText 'CopyName'
    $copySummary = Get-AppCopyText 'CopySummary'
    $copyDetails = Get-AppCopyText 'CopyDetails'
    if (-not $copyName -or $copySummary -notlike '*Last checked (UTC):*' -or $copySummary -like '*ClientService*' -or $copyDetails -notlike '*ClientService*') { throw 'Row-copy commands do not distinguish name, summary, and detailed evidence.' }
    $skippedBefore = @{}
    foreach ($row in $script:app.Rows | Where-Object Status -ne 'VERIFICATION PENDING') { $skippedBefore[$row.ComputerName] = ConvertTo-Json -InputObject $row -Compress }

    # Leave the original input untouched. The application must carry the saved
    # requests forward automatically, without any changes to paths or settings.
    $originalInput = $script:inputPath.Box.Text
    $script:menuItems['Verify'].PerformClick(); Wait-DemoWave
    if ($script:app.Done -ne 4 -or $script:app.WorkIndices.Count -ne 4) { throw 'Verification-only wave assessed non-pending computers.' }
    if ($script:percentLabel.Text -ne '100%') { throw 'Overall percentage must use selected work count, not all campaign rows.' }
    foreach ($row in $script:app.Rows | Where-Object { $skippedBefore.ContainsKey($_.ComputerName) }) {
        if ((ConvertTo-Json -InputObject $row -Compress) -ne $skippedBefore[$row.ComputerName]) { throw "Verification wave modified skipped finding: $($row.ComputerName)" }
    }
    foreach ($row in @(Read-ValidationInput $script:app.UnfinishedPath)) {
        if ((ConvertTo-Json -InputObject $row -Compress) -ne $skippedBefore[$row.ComputerName]) { throw "Verification wave changed or lost a skipped CSV record: $($row.ComputerName)" }
    }
    if ($script:inputPath.Box.Text -ne $originalInput -or $script:startButton.Text -notlike 'Check pending*') { throw 'Automatic continuation changed the input path or omitted the verification action.' }
    if ($script:inputPath.Box.Enabled -or $script:unfinishedPath.Box.Enabled) { throw 'Campaign paths must remain locked until New list.' }
    if (@(Import-Csv -LiteralPath $script:app.FinishedPath).Count -ne 4) { throw 'Second wave must produce four PASS results.' }
    if (@(Import-Csv -LiteralPath $script:app.UnfinishedPath).Count -ne 8) { throw 'Second wave must retain eight unfinished computers.' }
    $csvRows = @(Import-Csv -LiteralPath $script:app.FinishedPath)
    if ($csvRows[0].CheckedAtUtc -notmatch '^\d{8} \d{2}:\d{2}:\d{2}$') { throw 'Report timestamp formatting mismatch.' }
    if ($script:table.Rows[0]['Last checked (UTC)'] -notmatch '^\d{8} \d{2}:\d{2}:\d{2}$') { throw 'Grid timestamp formatting mismatch.' }
    if ($script:grid.Columns['Missing'].HeaderText -ne 'Updates') { throw 'Update column labeling mismatch.' }
    if ($csvRows[0].UpdateScope -ne 'Software Center-visible Windows OS and .NET patches' -or $csvRows[0].MissingCount -ne '0') { throw 'Report does not use Software Center-visible scope.' }
    if ($csvRows[0].PSObject.Properties.Name -contains 'UpdateStoreMissingCount') { throw 'Broader store fields must not appear in reports.' }
    Write-Output 'PASS: second-wave verification, same-file updates without prompts, formatted timestamps'
    $reportStamp = [IO.File]::GetLastWriteTimeUtc($script:app.UnfinishedPath)
    Start-AppWave
    if ($script:app.Running -or [IO.File]::GetLastWriteTimeUtc($script:app.UnfinishedPath) -ne $reportStamp -or $script:footer.Text -notlike '*still require attention*') { throw 'No pending work must not rescan known findings or imply campaign completion.' }
    Write-Output 'PASS: verification-only scope, unchanged skipped rows, and no-work attention summary'
    if ($script:binding.Count -ne 8) { throw 'Default unfinished view must hide the four PASS results.' }
    if ($script:heartbeatCount -lt 10) { throw 'UI message loop did not stay active during background saves.' }
    if ($script:app.Checkpoints -ge 24) { throw 'Checkpoints were not batched.' }
    Write-Output 'PASS: GUI heartbeat during delayed report writes, durable dispatch barrier, and batched checkpoints'

    Invoke-AppCommand 'Filter|PASS'
    if (-not $script:filterMenuItems['PASS'].Checked -or $script:filterMenuItems['Unfinished'].Checked) { throw 'View menu filter checks are out of sync.' }
    $script:binding.Sort = 'Computer DESC'
    $expectedNames = @($script:binding.List | ForEach-Object { $_.Row['Computer'] })
    $statusPath = Join-Path $script:testFolder 'Status.csv'
    Start-StatusExport $statusPath
    $script:filter.SelectedItem = 'Unfinished'
    Wait-StatusExport
    $statusRows = @(Import-Csv -LiteralPath $statusPath)
    if ($statusRows.Count -ne 4 -or ($statusRows.Computer -join '|') -ne ($expectedNames -join '|')) { throw 'Export must capture the selected filter and sort order at click time.' }
    if (($statusRows[0].PSObject.Properties.Name -join '|') -ne 'Computer|Status|Reason / current step|Updates|Reboot|Last checked (UTC)') { throw 'Status export must contain only displayed table columns.' }
    $script:filter.SelectedItem = 'PASS'; $script:search.Text = $expectedNames[0]
    Start-StatusExport $statusPath; Wait-StatusExport
    if (@(Import-Csv -LiteralPath $statusPath).Count -ne 1) { throw 'Export must honor search text.' }
    $script:search.Text = 'NO-SUCH-COMPUTER'
    Start-StatusExport $statusPath; Wait-StatusExport
    if (@(Import-Csv -LiteralPath $statusPath).Count) { throw 'Empty filtered view must export headers only.' }
    $blocked = $false
    try { Start-StatusExport $script:app.UnfinishedPath } catch { $blocked = $true }
    if (-not $blocked) { throw 'Display exports must not overwrite tracking reports.' }
    Invoke-AppCommand 'ResetView'
    if ($script:filter.Text -ne 'Unfinished' -or $script:search.Text -or $script:binding.Sort) { throw 'Reset view failed to restore default filtering/search/sort.' }
    Write-Output 'PASS: filtered/sorted snapshot export, search, empty view, and tracking-file protection'

    # Simulate reopening the application with only its saved local settings.
    $script:app.CampaignStarted = $false; $script:app.Rows = @(); $script:app.Finished = @{}
    Restore-AppSession
    if (-not $script:app.CampaignStarted -or $script:app.Rows.Count -ne 8 -or $script:app.Finished.Count -ne 4) { throw 'Saved campaign did not restore the remaining queue and finished results.' }
    if (([IO.File]::ReadAllText($script:app.SessionPath)) -match 'Password|Credential') { throw 'Session file contains credential fields.' }
    $badSession = Join-Path $script:testFolder 'Invalid-Session.json'
    $badSettings = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:app.SessionPath))
    $badSettings.UnfinishedPath = Join-Path $script:testFolder 'Missing.csv'
    [IO.File]::WriteAllText($badSession,(ConvertTo-Json -InputObject $badSettings))
    $blocked = $false
    try { Restore-AppSession -Path $badSession -Persist } catch { $blocked = $true }
    if (-not $blocked -or $script:app.Rows.Count -ne 8 -or $script:app.Finished.Count -ne 4 -or $script:app.RecoveryFailed) { throw 'Invalid resume must preserve the current campaign.' }
    $importedSession = Join-Path $script:testFolder 'Imported-Session.json'
    Copy-Item -LiteralPath $script:app.SessionPath -Destination $importedSession
    Restore-AppSession -Path $importedSession -Persist
    if ($script:inputPath.Box.Text -ne $originalInput -or -not [IO.File]::Exists($script:app.SessionPath)) { throw 'Explicit resume did not retain settings for restart.' }
    $script:menuItems['Reassess'].PerformClick(); Wait-DemoWave
    if ($script:app.Done -ne 8 -or @($script:app.Rows | Where-Object Status -eq 'PASS').Count) { throw 'Later wave rechecked finished computers.' }
    if ($script:table.Rows.Count -ne 12) { throw 'Finished computers must remain viewable.' }
    if ($script:statusCountLabels['PASS'].Text -ne '4  PASS') { throw 'PASS summary must retain the campaign finished count.' }
    $bitmap = [Drawing.Bitmap]::new($script:form.Width,$script:form.Height)
    try { $script:form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height)); $bitmap.Save((Join-Path $script:testFolder 'GUI-preview.png')) }
    finally { $bitmap.Dispose() }
    Write-Output 'PASS: session recovery, original input unchanged, finished computers excluded from later waves but viewable'

    # Simulate resolving one known issue. Reassessment discovers its clean state
    # and creates a request; only the following verification wave may pass it.
    $savedWorker = $script:workerSource
    $remediated = @'
        if ($Name -eq 'SRV-APP01') {
            if ($r.ScanRequestedAtUtc) { $r.Status = 'PASS'; $r.Verification = 'DEMO CONFIRMED'; $r.Reason = 'DEMO: remediation verified.' }
            else { $r.Status = 'VERIFICATION PENDING'; $r.ScanRequestedAtUtc = $r.CheckedAtUtc; $r.Verification = 'DEMO REQUESTED'; $r.Reason = 'DEMO: remediation requires verification.' }
            return $r
        }
        switch ($number % 6) {
'@
    $script:workerSource = $script:workerSource.Replace('switch ($number % 6) {',$remediated)
    if ($script:workerSource -eq $savedWorker) { throw 'Remediation test worker was not injected.' }
    Start-AppWave -Mode Unfinished; Wait-DemoWave
    if ($script:app.Done -ne 8 -or @($script:app.Rows | Where-Object Status -eq 'VERIFICATION PENDING').Count -ne 1) { throw 'Reassessment must rediscover the remediated computer without passing it immediately.' }
    Start-AppWave; Wait-DemoWave
    if ($script:app.Done -ne 1 -or $script:app.Finished.Count -ne 5 -or @(Import-Csv -LiteralPath $script:app.UnfinishedPath).Count -ne 7) { throw 'Verification after remediation assessed other known findings or failed to finish the remediated computer.' }
    $script:workerSource = $savedWorker
    Write-Output 'PASS: explicit resume validation and remediation -> reassessment -> verification workflow'

    # An empty unfinished report means completion, not a reset to the inventory.
    foreach ($row in $script:app.Rows) { $row.Status = 'PASS' }
    Save-AppReports
    Start-AppWave
    if ($script:app.Running -or $script:app.Rows.Count -or $script:app.Finished.Count -ne 12) { throw 'Completed campaign restarted server assessments.' }
    Write-Output 'PASS: completed campaign starts no workers'
    Reset-AppCampaign
    if ([IO.File]::Exists($script:app.SessionPath) -or -not $script:inputPath.Box.Enabled) { throw 'New list did not clear local settings and unlock setup.' }
    if (-not [IO.File]::Exists($script:app.UnfinishedPath)) { throw 'New list deleted a report.' }

    $script:inputPath.Box.Text = Join-Path $testRoot 'Computers.example.csv'
    $script:finishedPath.Box.Text = Join-Path $script:testFolder 'Finished-stop.csv'
    $script:unfinishedPath.Box.Text = Join-Path $script:testFolder 'Unfinished-stop.csv'
    Start-AppWave
    $deadline = [datetime]::UtcNow.AddSeconds(15)
    while ($script:app.Workers.Count -lt 2 -and [datetime]::UtcNow -lt $deadline) {
        Invoke-AppTick; [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(25)
    }
    if ($script:app.Workers.Count -ne 2) { throw 'Stop test failed to start two active workers.' }
    $script:app.Stopping = $true
    Wait-DemoWave
    if ($script:app.Done -ne 2 -or @($script:app.Rows | Where-Object Status -eq 'QUEUED').Count -ne 10) { throw 'Graceful stop did not retain queued computers.' }
    Write-Output 'PASS: graceful stop finishes active workers and preserves queued rows'
    Reset-AppCampaign
    Start-AppWave; Invoke-AppTick
    $script:app.Stopping = $true
    Wait-DemoWave
    if ($script:app.Done -ne 0 -or @($script:app.Rows | Where-Object Status -eq 'QUEUED').Count -ne 12) { throw 'Stopping during a checkpoint must cancel undispatched work safely.' }
    Write-Output 'PASS: stop during checkpoint cancels staged dispatch and preserves original tracking'

    # A larger synthetic list exercises copying/checkpointing without contacting
    # endpoints. Stop before dispatch, while the background report writer is busy.
    Reset-AppCampaign
    $scaleInput = Join-Path $script:testFolder 'Scale.csv'
    $scaleNames = @('ComputerName') + @(1..500 | ForEach-Object { 'SCALE-{0:D4}' -f $_ })
    [IO.File]::WriteAllLines($scaleInput,$scaleNames)
    $script:inputPath.Box.Text = $scaleInput
    $script:finishedPath.Box.Text = Join-Path $script:testFolder 'Scale-Finished.csv'
    $script:unfinishedPath.Box.Text = Join-Path $script:testFolder 'Scale-Unfinished.csv'
    Start-AppWave
    $tickClock = [Diagnostics.Stopwatch]::StartNew()
    Invoke-AppTick; $tickClock.Stop()
    if (-not $script:app.ReportJob -or $script:app.Workers.Count) { throw 'Large-list checkpoint bypassed the dispatch barrier.' }
    $heartbeatBefore = $script:heartbeatCount
    $script:app.Stopping = $true
    Wait-DemoWave
    if ($script:heartbeatCount -le $heartbeatBefore -or $script:app.Rows.Count -ne 500 -or $script:app.Done) { throw 'Large-list checkpoint blocked the message loop or dispatched stopped work.' }
    if (@(Import-Csv -LiteralPath $script:app.UnfinishedPath | Where-Object { $_.Status -ne 'QUEUED' -or $_.Verification }).Count) { throw 'Large-list stop lost original queue/tracking state.' }
    Write-Output "PASS: 500-computer checkpoint, UI heartbeat, and safe cancellation (first tick: $($tickClock.ElapsedMilliseconds) ms)"

    # Fail a background write and verify that none of the staged workers starts.
    Reset-AppCampaign
    $script:inputPath.Box.Text = Join-Path $testRoot 'Computers.example.csv'
    $script:finishedPath.Box.Text = Join-Path $script:testFolder 'Error-Finished.csv'
    $script:unfinishedPath.Box.Text = Join-Path $script:testFolder 'Error-Unfinished.csv'
    $script:app.Helpers += "`r`nfunction Save-WaveReports { throw 'TEST: report writer failure' }"
    $script:expectedErrors = @()
    function Show-AppError { param([string]$Message) $script:expectedErrors += $Message }
    Start-AppWave; Invoke-AppTick
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    while ($script:app.Running -and [datetime]::UtcNow -lt $deadline) {
        Invoke-AppTick; [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(25)
    }
    if ($script:app.Running -or -not $script:app.FatalSave -or $script:app.Done -or $script:app.Workers.Count -or -not $script:expectedErrors.Count) { throw 'Background save failure did not stop dispatch and release the wave.' }
    $blocked = $false
    try { Start-AppWave } catch { $blocked = $true }
    if (-not $blocked) { throw 'A failed checkpoint must not allow another wave without recovery.' }
    Write-Output 'PASS: background writer failure stops dispatch, reports the error, and blocks unsafe continuation'
    $script:heartbeat.Stop(); $script:heartbeat.Dispose()
    $script:form.Hide()
    Write-Output "GUI evidence saved: $script:testFolder"
}
$source = [IO.File]::ReadAllText((Join-Path $testRoot 'Start-ServerUpdateValidation.ps1'))
# Load trusted local helper text in-memory for this test harness only. No execution
# policy settings are changed, and the production launcher uses ordinary -File.
foreach ($helperName in @('Validation.Core.ps1','UI.Theme.ps1','UI.Commands.ps1')) {
    $source = $source.Replace(". (Join-Path `$PSScriptRoot '$helperName')", ". ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path `$PSScriptRoot '$helperName'))))")
}
$source = $source.Replace('$PSScriptRoot',("'" + $testRoot.Replace("'","''") + "'"))
$source = $source.Replace('[Windows.Forms.Application]::Run($script:form)', 'Invoke-InterfaceSmoke')
& ([scriptblock]::Create($source)) -Demo
