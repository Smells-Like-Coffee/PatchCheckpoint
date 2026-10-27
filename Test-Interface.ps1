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
    $deadline = [datetime]::UtcNow.AddSeconds(30)
    while ($script:app.Running -and [datetime]::UtcNow -lt $deadline) {
        Invoke-AppTick
        [Windows.Forms.Application]::DoEvents()
        [Threading.Thread]::Sleep(50)
        if ($script:app.Workers.Count -gt 2) { throw 'Concurrency exceeded requested limit.' }
    }
    if ($script:app.Running -or $script:app.FatalSave) { throw 'Demo wave failed to complete.' }
}
function Invoke-InterfaceSmoke {
    $script:app.SessionPath = Join-Path $script:testFolder 'Test-Session.json'
    $script:finishedPath.Box.Text = Join-Path $script:testFolder 'Finished.csv'
    $script:unfinishedPath.Box.Text = Join-Path $script:testFolder 'Unfinished.csv'
    $script:concurrency.Value = 2
    $script:form.Show()
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
    Start-AppWave
    Invoke-AppTick
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

    # Leave the original input untouched. The application must carry the saved
    # requests forward automatically, without any changes to paths or settings.
    $originalInput = $script:inputPath.Box.Text
    Start-AppWave; Wait-DemoWave
    if ($script:inputPath.Box.Text -ne $originalInput -or $script:startButton.Text -ne 'Run next wave') { throw 'Automatic wave continuation changed the inventory path or omitted the next-wave action.' }
    if ($script:inputPath.Box.Enabled -or $script:unfinishedPath.Box.Enabled) { throw 'Campaign paths must remain locked until New list.' }
    if (@(Import-Csv -LiteralPath $script:app.FinishedPath).Count -ne 4) { throw 'Second wave must produce four PASS results.' }
    if (@(Import-Csv -LiteralPath $script:app.UnfinishedPath).Count -ne 8) { throw 'Second wave must retain eight unfinished computers.' }
    $csvRows = @(Import-Csv -LiteralPath $script:app.FinishedPath)
    if ($csvRows[0].CheckedAtUtc -notmatch '^\d{8} \d{2}:\d{2}:\d{2}$') { throw 'Report timestamp formatting mismatch.' }
    if ($script:table.Rows[0]['Last checked (UTC)'] -notmatch '^\d{8} \d{2}:\d{2}:\d{2}$') { throw 'Grid timestamp formatting mismatch.' }
    if ($script:grid.Columns['Missing'].HeaderText -ne 'Updates') { throw 'Update column labeling mismatch.' }
    if ($csvRows[0].UpdateScope -ne 'Software Center-visible SCCM updates' -or $csvRows[0].MissingCount -ne '0') { throw 'Report does not use Software Center-visible scope.' }
    if ($csvRows[0].PSObject.Properties.Name -contains 'UpdateStoreMissingCount') { throw 'Broader store fields must not appear in reports.' }
    Write-Output 'PASS: second-wave verification, same-file updates without prompts, formatted timestamps'

    # Simulate reopening the application with only its saved local settings.
    $script:app.CampaignStarted = $false; $script:app.Rows = @(); $script:app.Finished = @{}
    Restore-AppSession
    if (-not $script:app.CampaignStarted -or $script:app.Rows.Count -ne 8 -or $script:app.Finished.Count -ne 4) { throw 'Saved campaign did not restore the remaining queue and finished results.' }
    if (([IO.File]::ReadAllText($script:app.SessionPath)) -match 'Password|Credential') { throw 'Session file contains credential fields.' }
    Start-AppWave; Wait-DemoWave
    if ($script:app.Done -ne 8 -or @($script:app.Rows | Where-Object Status -eq 'PASS').Count) { throw 'Later wave rechecked finished computers.' }
    if ($script:table.Rows.Count -ne 12) { throw 'Finished computers must remain viewable.' }
    if ($script:statusCountLabels['PASS'].Text -ne '4  PASS') { throw 'PASS summary must retain the campaign finished count.' }
    $bitmap = [Drawing.Bitmap]::new($script:form.Width,$script:form.Height)
    try { $script:form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height)); $bitmap.Save((Join-Path $script:testFolder 'GUI-preview.png')) }
    finally { $bitmap.Dispose() }
    Write-Output 'PASS: session recovery, original input unchanged, finished computers excluded from later waves but viewable'

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
    Start-AppWave; Invoke-AppTick
    $script:app.Stopping = $true
    Wait-DemoWave
    if ($script:app.Done -ne 2 -or @($script:app.Rows | Where-Object Status -eq 'QUEUED').Count -ne 10) { throw 'Graceful stop did not retain queued computers.' }
    Write-Output 'PASS: graceful stop finishes active workers and preserves queued rows'
    $script:form.Hide()
    Write-Output "GUI evidence saved: $script:testFolder"
}
$source = [IO.File]::ReadAllText((Join-Path $testRoot 'Start-ServerUpdateValidation.ps1'))
# Load trusted local helper text in-memory for this test harness only. No execution
# policy settings are changed, and the production launcher uses ordinary -File.
foreach ($helperName in @('Validation.Core.ps1','UI.Theme.ps1')) {
    $source = $source.Replace(". (Join-Path `$PSScriptRoot '$helperName')", ". ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path `$PSScriptRoot '$helperName'))))")
}
$source = $source.Replace('$PSScriptRoot',("'" + $testRoot.Replace("'","''") + "'"))
$source = $source.Replace('[Windows.Forms.Application]::Run($script:form)', 'Invoke-InterfaceSmoke')
& ([scriptblock]::Create($source)) -Demo
