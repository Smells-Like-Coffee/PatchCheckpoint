<#
.SYNOPSIS
    Provides native menus, keyboard shortcuts, local help, and row-copy actions.
.DESCRIPTION
    Routes menus and visible buttons to the same campaign functions. Menu state
    prevents conflicting changes during a wave. Help reads packaged local text;
    clipboard commands run only when explicitly selected by the operator.
#>
$script:menuItems = @{}
$script:filterMenuItems = @{}

function New-AppMenuItem {
    param($Parent,[string]$Text,[string]$Command,[Windows.Forms.Keys]$Shortcut = [Windows.Forms.Keys]::None)
    $item = [Windows.Forms.ToolStripMenuItem]::new($Text)
    $item.Tag = $Command; $item.ShortcutKeys = $Shortcut
    $item.Add_Click({ param($sender,$eventArgs) Invoke-AppCommand ([string]$sender.Tag) })
    [void]$Parent.DropDownItems.Add($item)
    $script:menuItems[$Command] = $item
    $item
}

function Initialize-AppMenus {
    $script:menu = [Windows.Forms.MenuStrip]::new()
    $script:menu.BackColor = [Drawing.Color]::FromArgb(244,248,253)
    $script:menu.ForeColor = [Drawing.Color]::FromArgb(16,38,70)
    $script:form.MainMenuStrip = $script:menu; $script:form.Controls.Add($script:menu)
    $file = [Windows.Forms.ToolStripMenuItem]::new('&File')
    $actions = [Windows.Forms.ToolStripMenuItem]::new('&Actions')
    $view = [Windows.Forms.ToolStripMenuItem]::new('&View')
    $help = [Windows.Forms.ToolStripMenuItem]::new('&Help')
    [void]$script:menu.Items.AddRange(@($file,$actions,$view,$help))
    [void](New-AppMenuItem $file '&New campaign...' 'New' 'Control,N')
    [void](New-AppMenuItem $file '&Resume campaign...' 'Resume' 'Control,O')
    [void]$file.DropDownItems.Add([Windows.Forms.ToolStripSeparator]::new())
    [void](New-AppMenuItem $file '&Export Report...' 'Export' 'Control,E')
    $folders = [Windows.Forms.ToolStripMenuItem]::new('Open reports folder')
    [void]$file.DropDownItems.Add($folders)
    [void](New-AppMenuItem $folders 'Finished report folder' 'FolderFinished')
    [void](New-AppMenuItem $folders 'Unfinished report folder' 'FolderUnfinished')
    [void]$file.DropDownItems.Add([Windows.Forms.ToolStripSeparator]::new())
    [void](New-AppMenuItem $file 'E&xit' 'Exit' 'Alt,F4')
    [void](New-AppMenuItem $actions 'Run &initial assessment' 'Initial')
    [void](New-AppMenuItem $actions 'Check pending &verification' 'Verify')
    [void](New-AppMenuItem $actions '&Reassess unfinished' 'Reassess')
    [void](New-AppMenuItem $actions '&Stop after active checks' 'Stop')
    [void]$actions.DropDownItems.Add([Windows.Forms.ToolStripSeparator]::new())
    [void](New-AppMenuItem $actions 'Set &credentials...' 'Credentials')
    $status = [Windows.Forms.ToolStripMenuItem]::new('Status &filter')
    [void]$view.DropDownItems.Add($status)
    foreach ($name in $script:filter.Items) {
        $item = New-AppMenuItem $status ([string]$name) ('Filter|' + $name)
        $script:filterMenuItems[[string]$name] = $item
    }
    [void](New-AppMenuItem $view '&Find computer' 'Find' 'Control,F')
    [void](New-AppMenuItem $view '&Clear search' 'ClearSearch')
    [void](New-AppMenuItem $view 'Show &details pane' 'Details')
    [void](New-AppMenuItem $view 'Show &wave setup pane' 'Setup')
    [void](New-AppMenuItem $view 'Show concurrent check &progress' 'WorkerProgress')
    [void](New-AppMenuItem $view '&Reset view' 'ResetView')
    [void](New-AppMenuItem $help '&User guide' 'Guide' 'F1')
    [void](New-AppMenuItem $help '&Troubleshooting' 'Troubleshooting')
    [void](New-AppMenuItem $help '&Release notes' 'ReleaseNotes')
    [void](New-AppMenuItem $help '&Diagnostic Export...' 'Diagnostics')
    [void](New-AppMenuItem $help 'Open &GitHub repository' 'Repository')
    [void]$help.DropDownItems.Add([Windows.Forms.ToolStripSeparator]::new())
    [void](New-AppMenuItem $help '&About' 'About')
    foreach ($parent in @($file,$actions,$view,$help,$status,$folders)) { $parent.Add_DropDownOpening({ Update-AppCommandState }) }

    $script:rowMenu = [Windows.Forms.ContextMenuStrip]::new()
    foreach ($entry in @(@('Copy computer name','CopyName'),@('Copy status summary','CopySummary'),@('Copy detailed results','CopyDetails'))) {
        $item = [Windows.Forms.ToolStripMenuItem]::new($entry[0]); $item.Tag = $entry[1]
        $item.Add_Click({ param($sender,$eventArgs) Invoke-AppCommand ([string]$sender.Tag) })
        [void]$script:rowMenu.Items.Add($item); $script:menuItems[$entry[1]] = $item
    }
    $script:rowMenu.Add_Opening({ Update-AppCommandState })
    $script:grid.ContextMenuStrip = $script:rowMenu
    $script:grid.Add_CellMouseDown({
        param($sender,$eventArgs)
        if ($eventArgs.Button -ne [Windows.Forms.MouseButtons]::Right) { return }
        $sender.ClearSelection()
        if ($eventArgs.RowIndex -ge 0) {
            $sender.CurrentCell = $sender.Rows[$eventArgs.RowIndex].Cells['Computer']
            $sender.Rows[$eventArgs.RowIndex].Selected = $true
        }
    })
    Update-AppCommandState
    Initialize-AppToolTips
}

function Update-AppCommandState {
    if (-not $script:menuItems.Count) { return }
    $idle = -not $script:app.Running
    $canRun = $idle -and -not $script:app.FatalSave -and -not $script:app.RecoveryFailed
    $script:menuItems['New'].Enabled = $idle -and -not $script:app.ExportJob -and -not $script:app.DiagnosticJob
    $script:menuItems['Resume'].Enabled = $script:menuItems['New'].Enabled
    $script:menuItems['Initial'].Enabled = $canRun -and -not $script:app.CampaignStarted
    $script:menuItems['Verify'].Enabled = $canRun -and $script:app.CampaignStarted
    $script:menuItems['Reassess'].Enabled = $script:menuItems['Verify'].Enabled
    $script:menuItems['Stop'].Enabled = $script:app.Running -and -not $script:app.Stopping
    $script:menuItems['Credentials'].Enabled = $idle -and -not $Demo
    $script:menuItems['Export'].Enabled = -not $script:app.ExportJob
    $script:menuItems['Diagnostics'].Enabled = -not $script:app.DiagnosticJob
    $script:menuItems['Diagnostics'].ToolTipText = 'Create a local support ZIP with campaign evidence, runtime settings, saved reports and recent errors. Contains infrastructure details; no endpoint queries.'
    $script:menuItems['FolderFinished'].Enabled = -not [string]::IsNullOrWhiteSpace($script:finishedPath.Box.Text)
    $script:menuItems['FolderUnfinished'].Enabled = -not [string]::IsNullOrWhiteSpace($script:unfinishedPath.Box.Text)
    $sameFolder = $false
    if ($script:menuItems['FolderFinished'].Enabled -and $script:menuItems['FolderUnfinished'].Enabled) {
        try { $sameFolder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:finishedPath.Box.Text)) -eq [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:unfinishedPath.Box.Text)) } catch { $sameFolder = $false }
    }
    $script:menuItems['FolderFinished'].Text = if ($sameFolder) { 'Reports folder' } else { 'Finished report folder' }
    $script:menuItems['FolderUnfinished'].Visible = -not $sameFolder
    $script:menuItems['Details'].Checked = $script:app.DetailsVisible
    $script:menuItems['Setup'].Checked = -not $script:app.SetupCollapsed
    $script:menuItems['WorkerProgress'].Checked = $script:app.ShowWorkerProgress
    foreach ($name in $script:filterMenuItems.Keys) { $script:filterMenuItems[$name].Checked = $script:filter.Text -eq $name }
    foreach ($key in @('CopyName','CopySummary','CopyDetails')) { $script:menuItems[$key].Enabled = $script:grid.SelectedRows.Count -eq 1 }
    $script:startButton.Enabled = $canRun
    $script:reassessButton.Enabled = $canRun -and $script:app.CampaignStarted
    $script:loadButton.Enabled = $idle -and -not $script:app.ExportJob -and -not $script:app.DiagnosticJob
}

function Show-StatusExportDialog {
    $dialog = [Windows.Forms.SaveFileDialog]::new()
    $dialog.Filter = 'Excel workbook - all statuses (*.xlsx)|*.xlsx|CSV - current view (*.csv)|*.csv'
    $dialog.DefaultExt = 'xlsx'; $dialog.FileName = 'Computer-Status'
    if ([IO.Directory]::Exists($script:campaignFolder.Box.Text)) { $dialog.InitialDirectory = $script:campaignFolder.Box.Text }
    try { if ($dialog.ShowDialog($script:form) -eq 'OK') { Start-StatusExport $dialog.FileName } }
    finally { $dialog.Dispose() }
}

# Copy text is built from the actual selected row, including sorted/filtered views.
# The separate text function can be tested without reading or replacing a clipboard.
function Get-AppCopyText {
    param([ValidateSet('CopyName','CopySummary','CopyDetails')][string]$Command)
    if ($script:grid.SelectedRows.Count -ne 1) { throw 'Select one computer first.' }
    $selected = $script:grid.SelectedRows[0]
    $name = [string]$selected.Cells['Computer'].Value
    if ($Command -eq 'CopyName') { return $name }
    if ($Command -eq 'CopySummary') {
        return (@($script:grid.Columns | Where-Object Visible | Sort-Object DisplayIndex | ForEach-Object { '{0}: {1}' -f $_.HeaderText,$selected.Cells[$_.Name].Value }) -join [Environment]::NewLine)
    }
    $row = @($script:app.Rows | Where-Object ComputerName -eq $name)
    if (-not $row.Count -and $script:app.Finished.ContainsKey($name)) { $row = @($script:app.Finished[$name]) }
    if ($row.Count -ne 1) { throw 'Selected computer is no longer available.' }
    Format-ValidationDetails $row[0]
}

function Reset-AppView {
    $script:filter.SelectedItem = 'Unfinished'; $script:search.Clear(); $script:binding.Sort = ''
    $weights = @(18,26,45,10,10,26)
    for ($index = 0; $index -lt $script:grid.Columns.Count; $index++) {
        $column = $script:grid.Columns[$index]; $column.DisplayIndex = $index; $column.FillWeight = $weights[$index]
        $column.HeaderCell.SortGlyphDirection = 'None'
    }
    Update-AppCommandState
}

function Get-AppHelpText {
    param([ValidateSet('Guide','Troubleshooting','ReleaseNotes','About')][string]$Topic)
    if ($Topic -eq 'About') {
        return "Patch Checkpoint $script:AppVersion`r`nWindows PowerShell $($PSVersionTable.PSVersion), $([IntPtr]::Size * 8)-bit`r`n.NET CLR $([Environment]::Version)`r`n`r`nChecks Software Center-visible Windows OS/.NET patches and strict OS pending-reboot indicators; PFRO is ignored.`r`n`r`nThe sole remote state change is the client verification scan (schedule 113). No updates are installed and no computers are restarted.`r`n`r`nCredentials are retained only in memory. See the User guide and SECURITY.md for scope and limitations.`r`n`r`nCreated with AI assistance using OpenAI Codex; requirements, review, and operational testing are directed by the project owner."
    }
    $name = switch ($Topic) { 'Guide' { 'USER-GUIDE.md' }; 'Troubleshooting' { 'TROUBLESHOOTING.md' }; 'ReleaseNotes' { 'CHANGELOG.md' } }
    [IO.File]::ReadAllText((Join-Path $script:ProjectRoot $name))
}

function Show-AppHelp {
    param([string]$Topic)
    $text = Get-AppHelpText $Topic
    $dialog = [Windows.Forms.Form]::new(); $dialog.Text = 'Patch Checkpoint - ' + $Topic
    $dialog.Size = [Drawing.Size]::new(850,650); $dialog.MinimumSize = [Drawing.Size]::new(550,350)
    $dialog.StartPosition = 'CenterParent'
    $body = [Windows.Forms.RichTextBox]::new(); $body.Dock = 'Fill'; $body.ReadOnly = $true
    $body.DetectUrls = $false; $body.BackColor = [Drawing.Color]::White; $body.Font = [Drawing.Font]::new('Segoe UI',10)
    $body.Text = $text; $body.SelectionStart = 0
    $dialog.Controls.Add($body)
    try { [void]$dialog.ShowDialog($script:form) } finally { $dialog.Dispose() }
}

function Invoke-AppCommand {
    param([string]$Command)
    try {
        if ($Command.StartsWith('Filter|')) { $script:filter.SelectedItem = $Command.Substring(7); Update-AppCommandState; return }
        if ($script:menuItems.ContainsKey($Command) -and -not $script:menuItems[$Command].Enabled) { return }
        switch ($Command) {
            'New' { Reset-AppCampaign }
            'Resume' {
                $dialog = [Windows.Forms.OpenFileDialog]::new()
                $dialog.Filter = 'Campaign resume file (*.json)|*.json'; $dialog.FileName = 'Campaign.json'
                try { if ($dialog.ShowDialog($script:form) -eq 'OK') { Restore-AppSession -Path $dialog.FileName -Persist } } finally { $dialog.Dispose() }
            }
            'Export' { Show-StatusExportDialog }
            'Diagnostics' { Show-DiagnosticExportDialog }
            'FolderFinished' { Open-AppReportFolder $script:finishedPath.Box.Text }
            'FolderUnfinished' { Open-AppReportFolder $script:unfinishedPath.Box.Text }
            'Exit' { $script:form.Close() }
            'Initial' { Start-AppWave -Mode Initial }
            'Verify' { Start-AppWave -Mode Verification }
            'Reassess' { Start-AppWave -Mode Unfinished }
            'Stop' { $script:app.Stopping = $true; $script:stopButton.Enabled = $false }
            'Credentials' { Set-AppCredential }
            'Find' { $script:search.Focus(); $script:search.SelectAll() }
            'ClearSearch' { $script:search.Clear() }
            'Details' { $script:app.DetailsVisible = -not $script:app.DetailsVisible; Set-ValidationThemeLayout }
            'Setup' { $script:app.SetupCollapsed = -not $script:app.SetupCollapsed; Set-ValidationThemeLayout; Save-AppViewPreferences }
            'WorkerProgress' { $script:app.ShowWorkerProgress = -not $script:app.ShowWorkerProgress; Set-ValidationThemeLayout; Update-WorkerProgressDisplay; Save-AppViewPreferences }
            'ResetView' { Reset-AppView }
            { $_ -in @('CopyName','CopySummary','CopyDetails') } { [Windows.Forms.Clipboard]::SetText((Get-AppCopyText $Command)) }
            { $_ -in @('Guide','Troubleshooting','ReleaseNotes','About') } { Show-AppHelp $Command }
            'Repository' { [void][Diagnostics.Process]::Start('https://github.com/Smells-Like-Coffee/PatchCheckpoint') }
        }
        Update-AppCommandState
    }
    catch { Show-AppError $_.Exception.Message }
}

# Tooltips describe operator decisions, not implementation internals or secrets.
function Initialize-AppToolTips {
    foreach ($entry in @(
        @($script:inputPath,'ComputerName or SERVERNAME CSV. This is the only file you need to supply for a new campaign.'),
        @($script:campaignFolder,'Type or browse to the exact folder for this campaign. Finished.csv, Unfinished.csv, and Campaign.json are created there on startup. Locked once the campaign begins.'),
        @($script:finishedPath,'Created automatically in the selected campaign folder. Accumulates PASS results; optional location override before starting.'),
        @($script:unfinishedPath,'Created automatically with the finished report and Campaign.json. Latest findings and scan tracking; preserve the campaign folder.')
    )) {
        $path = $entry[0]; $text = $entry[1]
        $script:toolTips.SetToolTip($path.Label,$text); $script:toolTips.SetToolTip($path.Box,$text)
        $script:toolTips.SetToolTip($path.Button,'Choose the CSV location. ' + $text)
    }
    $tips = @(
        @($script:credentialButton,'Set the account used for remote checks. Credentials are kept in memory only.'),
        @($script:accountLabel,'Account for subsequent remote checks. Passwords are never displayed or saved.'),
        @($script:concurrency,'Maximum simultaneous computer checks, from 1 to 32. More workers can increase endpoint and network load.'),
        @($script:loadButton,'Preview a new inventory, or reset setup for another campaign. Existing reports are preserved.'),
        @($script:startButton,'Initial assessment includes one automatic verification follow-up after 60 seconds. Later clicks check only VERIFICATION PENDING computers.'),
        @($script:reassessButton,'Reassess every unfinished computer after investigation or remediation. PASS computers stay finished.'),
        @($script:stopButton,'Stop dispatching work. Active checks and the final report checkpoint finish before the wave stops.'),
        @($script:setupToggle,'Collapse or expand setup. Check actions remain visible in their own pane.'),
        @($script:exportButton,'Excel exports all campaign rows on status tabs. CSV exports the current filtered, searched, sorted table. Neither includes detailed tracking.'),
        @($script:filter,'Choose which computer statuses are displayed. This does not change wave selection.'),
        @($script:search,'Filter displayed computers by name. Search is combined with the chosen status filter.'),
        @($script:progress,'Overall progress for the computers selected in this wave. Completion does not mean all computers passed.'),
        @($script:summary,'Counts apply to this wave; status totals describe the full campaign.'),
        @($script:detail,'Evidence for the selected computer. Right-click a row to copy its summary or detailed results.'),
        @($script:grid,'Latest results. Click a row for details, click a header to sort, or right-click to copy.'),
        @($script:workerFlow,'Observed assessment stages for each worker slot. Marquee means waiting for progress; this does not measure patch installation.')
    )
    foreach ($tip in $tips) { $script:toolTips.SetToolTip($tip[0],$tip[1]) }
    foreach ($status in $script:statusCountLabels.Keys) { $script:toolTips.SetToolTip($script:statusCountLabels[$status],"Show only $status computers. The current search remains applied.") }
    $script:grid.ShowCellToolTips = $true
    foreach ($column in $script:grid.Columns) { $column.ToolTipText = $column.HeaderText + '. Export preserves the complete value, even when a cell is truncated.' }
    $script:menu.ShowItemToolTips = $true
    foreach ($key in $script:menuItems.Keys) {
        $script:menuItems[$key].ToolTipText = switch ($key) {
            'Setup' { 'Toggle the setup pane without hiding the separate check actions.' }
            'WorkerProgress' { 'Show or hide individual worker stage bars below overall progress.' }
            'Verify' { 'Assess only computers waiting for verification; preserve all other findings.' }
            'Reassess' { 'Check all unfinished computers after remediation; PASS computers are excluded.' }
            default { $script:menuItems[$key].Text.Replace('&','') }
        }
    }
}

function Save-AppViewPreferences {
    $script:app.ViewPreferencesDirty = $true
    if ($script:app.CampaignStarted -and -not $script:app.Running -and -not $script:app.FatalSave) { Save-AppSession }
}

function Open-AppReportFolder {
    param([string]$ReportPath)
    $folder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath))
    if (-not [IO.Directory]::Exists($folder)) { throw 'The reports folder does not exist.' }
    [void][Diagnostics.Process]::Start($folder)
}
