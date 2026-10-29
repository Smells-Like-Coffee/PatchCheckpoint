<#
.SYNOPSIS
    Exercises the actual compiled application without contacting endpoints.
.DESCRIPTION
    Invoked only by the EXE's explicit --self-test option. Uses synthetic workers,
    a private test campaign, the real message loop and export workers. Saves a JSON
    result beside the requested report, never production campaign data.
#>
function Invoke-ExecutableSmokeTest {
    $testFolder = Join-Path ([IO.Path]::GetDirectoryName($ExecutableTestReport)) ('EXE-Test-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($testFolder)
    $script:app.SessionPath = Join-Path $testFolder 'Test-Session.json'
    $script:campaignFolder.Box.Text = $testFolder
    $script:concurrency.Value = 2
    $script:app.InitialVerificationDelaySeconds = 1
    $script:form.Show()
    try {
        if ($script:AppVersion -ne '1.0.2' -or -not $script:CompiledHost -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'Incorrect compiled runtime or application version.' }
        if (-not $script:applicationIcon -or $script:form.Icon -ne $script:applicationIcon) { throw 'Application branding icon was not loaded.' }
        if (-not [IO.Directory]::GetAccessControl($script:ProjectRoot).AreAccessRulesProtected) { throw 'Embedded resource directory must have a private ACL.' }
        if (@(Get-Command Invoke-Command,New-PSSessionOption -ErrorAction Stop).Count -ne 2) { throw 'Required WinRM client commands are unavailable in the compiled host.' }
        foreach ($topic in @('Guide','Troubleshooting','ReleaseNotes','About')) { if ((Get-AppHelpText $topic).Length -lt 100) { throw ('Missing embedded help: ' + $topic) } }
        if ($script:footer.Parent -ne $script:activityBody) { throw 'Activity panel is unavailable.' }
        Start-AppWave
        $deadline = [datetime]::UtcNow.AddSeconds(90)
        while ($script:app.Running -and [datetime]::UtcNow -lt $deadline) {
            Invoke-AppTick; [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(40)
            if ($script:app.Workers.Count -gt 2) { throw 'Compiled host exceeded configured concurrency.' }
        }
        if ($script:app.Running -or $script:app.FatalSave -or $script:app.Finished.Count -ne 4) { throw 'Compiled assessment/automatic verification failed.' }
        $export = Join-Path $testFolder 'Status.xlsx'
        Start-StatusExport $export
        $diagnostic = Join-Path $testFolder 'Diagnostic.zip'
        Start-DiagnosticExport $diagnostic
        $deadline = [datetime]::UtcNow.AddSeconds(30)
        while (($script:app.ExportJob -or $script:app.DiagnosticJob) -and [datetime]::UtcNow -lt $deadline) {
            Invoke-AppTick; [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(40)
        }
        if ($script:app.ExportJob -or $script:app.DiagnosticJob -or -not [IO.File]::Exists($export) -or -not [IO.File]::Exists($diagnostic)) { throw 'Compiled exports failed.' }
        Restore-AppSession
        if ($script:app.Finished.Count -ne 4 -or $script:app.Rows.Count -ne 8) { throw 'Compiled campaign resume failed.' }
        $result = [ordered]@{
            Success = $true; Version = $script:AppVersion; CompiledHost = $script:CompiledHost
            PowerShell = $PSVersionTable.PSVersion.ToString(); Apartment = [Threading.Thread]::CurrentThread.ApartmentState.ToString()
            RuntimeRoot = $script:ProjectRoot; DataRoot = $script:DataRoot; TestFolder = $testFolder
            Finished = $script:app.Finished.Count; Unfinished = $script:app.Rows.Count
            ExcelExport = $export; DiagnosticExport = $diagnostic
            Checks = @('Application icon','Private runtime ACL','WinRM command availability','Embedded help','STA GUI','Bounded demo workers','Automatic verification','Excel export','Diagnostic ZIP','Campaign resume','Activity panel')
        }
        [IO.File]::WriteAllText($ExecutableTestReport,(ConvertTo-Json -InputObject $result -Depth 5))
    }
    finally { $script:form.Hide() }
}
