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
    [void](New-AppMenuItem $file '&Export current view...' 'Export' 'Control,E')
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
    [void](New-AppMenuItem $view '&Reset view' 'ResetView')
    [void](New-AppMenuItem $help '&User guide' 'Guide' 'F1')
    [void](New-AppMenuItem $help '&Troubleshooting' 'Troubleshooting')
    [void](New-AppMenuItem $help '&Release notes' 'ReleaseNotes')
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
}

function Update-AppCommandState {
    if (-not $script:menuItems.Count) { return }
    $idle = -not $script:app.Running
    $canRun = $idle -and -not $script:app.FatalSave -and -not $script:app.RecoveryFailed
    $script:menuItems['New'].Enabled = $idle -and -not $script:app.ExportJob
    $script:menuItems['Resume'].Enabled = $script:menuItems['New'].Enabled
    $script:menuItems['Initial'].Enabled = $canRun -and -not $script:app.CampaignStarted
    $script:menuItems['Verify'].Enabled = $canRun -and $script:app.CampaignStarted
    $script:menuItems['Reassess'].Enabled = $script:menuItems['Verify'].Enabled
    $script:menuItems['Stop'].Enabled = $script:app.Running -and -not $script:app.Stopping
    $script:menuItems['Credentials'].Enabled = $idle -and -not $Demo
    $script:menuItems['Export'].Enabled = -not $script:app.ExportJob
    $script:menuItems['FolderFinished'].Enabled = -not [string]::IsNullOrWhiteSpace($script:finishedPath.Box.Text)
    $script:menuItems['FolderUnfinished'].Enabled = -not [string]::IsNullOrWhiteSpace($script:unfinishedPath.Box.Text)
    $sameFolder = $false
    if ($script:menuItems['FolderFinished'].Enabled -and $script:menuItems['FolderUnfinished'].Enabled) {
        try { $sameFolder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:finishedPath.Box.Text)) -eq [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:unfinishedPath.Box.Text)) } catch { $sameFolder = $false }
    }
    $script:menuItems['FolderFinished'].Text = if ($sameFolder) { 'Reports folder' } else { 'Finished report folder' }
    $script:menuItems['FolderUnfinished'].Visible = -not $sameFolder
    $script:menuItems['Details'].Checked = $script:app.DetailsVisible
    foreach ($name in $script:filterMenuItems.Keys) { $script:filterMenuItems[$name].Checked = $script:filter.Text -eq $name }
    foreach ($key in @('CopyName','CopySummary','CopyDetails')) { $script:menuItems[$key].Enabled = $script:grid.SelectedRows.Count -eq 1 }
    $script:startButton.Enabled = $canRun
    $script:reassessButton.Enabled = $canRun -and $script:app.CampaignStarted
    $script:loadButton.Enabled = $idle -and -not $script:app.ExportJob
}

function Show-StatusExportDialog {
    $dialog = [Windows.Forms.SaveFileDialog]::new()
    $dialog.Filter = 'CSV files (*.csv)|*.csv'; $dialog.DefaultExt = 'csv'; $dialog.FileName = 'Computer-Status.csv'
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
        return "Server Update Validation $script:AppVersion`r`nWindows PowerShell $($PSVersionTable.PSVersion), $([IntPtr]::Size * 8)-bit`r`n.NET CLR $([Environment]::Version)`r`n`r`nChecks Software Center-visible waiting updates and Windows/SCCM pending reboot indicators.`r`n`r`nThe sole remote state change is the client verification scan (schedule 113). No updates are installed and no computers are restarted.`r`n`r`nCredentials are retained only in memory. See the User guide and SECURITY.md for scope and limitations."
    }
    $name = switch ($Topic) { 'Guide' { 'README.md' }; 'Troubleshooting' { 'TROUBLESHOOTING.md' }; 'ReleaseNotes' { 'CHANGELOG.md' } }
    [IO.File]::ReadAllText((Join-Path $script:ProjectRoot $name))
}

function Show-AppHelp {
    param([string]$Topic)
    $text = Get-AppHelpText $Topic
    $dialog = [Windows.Forms.Form]::new(); $dialog.Text = 'Server Update Validation - ' + $Topic
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
                $dialog.Filter = 'Campaign session (*.json)|*.json'; $dialog.FileName = 'Validation-Session.json'
                try { if ($dialog.ShowDialog($script:form) -eq 'OK') { Restore-AppSession -Path $dialog.FileName -Persist } } finally { $dialog.Dispose() }
            }
            'Export' { Show-StatusExportDialog }
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
            'ResetView' { Reset-AppView }
            { $_ -in @('CopyName','CopySummary','CopyDetails') } { [Windows.Forms.Clipboard]::SetText((Get-AppCopyText $Command)) }
            { $_ -in @('Guide','Troubleshooting','ReleaseNotes','About') } { Show-AppHelp $Command }
            'Repository' { [void][Diagnostics.Process]::Start('https://github.com/Smells-Like-Coffee/Invoke-ServerUpdateValidate') }
        }
        Update-AppCommandState
    }
    catch { Show-AppError $_.Exception.Message }
}

function Open-AppReportFolder {
    param([string]$ReportPath)
    $folder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath))
    if (-not [IO.Directory]::Exists($folder)) { throw 'The reports folder does not exist.' }
    [void][Diagnostics.Process]::Start($folder)
}
