<#
.SYNOPSIS
    Applies the light desktop visual design to Server Update Validation.
.DESCRIPTION
    Uses built-in Windows Forms and GDI+ for rounded cards, painted buttons, blue
    progress, readable tables, and accessible status badges. No external UI library
    or network resource is loaded. Theme functions change presentation only.
#>
if (-not ('ValidationUI.Card' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace ValidationUI
{
    // Reusable rounded paths are disposed by every caller after drawing.
    public static class Shapes
    {
        public static GraphicsPath Round(RectangleF r, float radius)
        {
            GraphicsPath p = new GraphicsPath();
            float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    public class Card : Panel
    {
        public Card()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Color.FromArgb(239, 244, 249);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Width < 3 || Height < 3) return;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(1, 1, Width - 3, Height - 3);
            using (GraphicsPath p = Shapes.Round(r, 7))
            using (LinearGradientBrush b = new LinearGradientBrush(r, Color.White,
                Color.FromArgb(250, 252, 255), LinearGradientMode.Vertical))
            using (Pen pen = new Pen(Color.FromArgb(213, 224, 237)))
            {
                e.Graphics.FillPath(b, p);
                e.Graphics.DrawPath(pen, p);
            }
        }
    }

    public class ActionButton : Button
    {
        private bool hover;
        private bool primary;
        public bool Primary { get { return primary; } set { primary = value; Invalidate(); } }
        public ActionButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (Width < 3 || Height < 3) return;
            e.Graphics.Clear(Parent == null ? SystemColors.Control : Parent.BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(1, 1, Width - 3, Height - 3);
            Color top = primary ? Color.FromArgb(0, 129, 239) : Color.White;
            Color bottom = primary ? Color.FromArgb(0, 101, 202) : Color.FromArgb(240, 245, 250);
            if (hover && Enabled) bottom = primary ? Color.FromArgb(0, 85, 180) : Color.FromArgb(224, 236, 250);
            if (!Enabled) { top = Color.FromArgb(244, 247, 250); bottom = Color.FromArgb(235, 240, 246); }
            using (GraphicsPath p = Shapes.Round(r, 5))
            using (LinearGradientBrush b = new LinearGradientBrush(r, top, bottom, LinearGradientMode.Vertical))
            using (Pen pen = new Pen(primary && Enabled ? Color.FromArgb(0, 104, 206) : Color.FromArgb(193, 207, 224)))
            {
                e.Graphics.FillPath(b, p);
                e.Graphics.DrawPath(pen, p);
            }
            Color text = !Enabled ? Color.FromArgb(142, 153, 168) :
                (primary ? Color.White : Color.FromArgb(17, 40, 75));
            TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -5, -5));
        }
    }

    public class BlueProgress : Control
    {
        private int maximum = 1;
        private int current;
        public int Maximum { get { return maximum; } set { maximum = Math.Max(1, value); Invalidate(); } }
        public int Value { get { return current; } set { current = Math.Max(0, Math.Min(value, maximum)); Invalidate(); } }
        public BlueProgress()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            AccessibleName = "Assessment progress";
            AccessibleRole = AccessibleRole.ProgressBar;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Width < 3 || Height < 3) return;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0, 0, Width - 1, Height - 1);
            using (GraphicsPath p = Shapes.Round(r, 4))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(224, 232, 241))) e.Graphics.FillPath(b, p);
            float w = r.Width * current / maximum;
            if (w < 1) return;
            RectangleF fill = new RectangleF(0, 0, w, r.Height);
            using (GraphicsPath p = Shapes.Round(fill, 4))
            using (LinearGradientBrush b = new LinearGradientBrush(fill, Color.FromArgb(0, 143, 246),
                Color.FromArgb(0, 105, 208), LinearGradientMode.Vertical)) e.Graphics.FillPath(b, p);
        }
    }

    public class StatusGrid : DataGridView
    {
        public StatusGrid() { DoubleBuffered = true; }
    }
}
'@
}

function New-ThemeHeading {
    param([Windows.Forms.Control]$Parent,[string]$Text)
    $label = [Windows.Forms.Label]::new()
    $label.Text = $Text; $label.ForeColor = [Drawing.Color]::FromArgb(14,39,76)
    $label.Font = [Drawing.Font]::new('Segoe UI',13,[Drawing.FontStyle]::Bold)
    $label.BackColor = [Drawing.Color]::Transparent
    $label.SetBounds(20,12,350,28); $Parent.Controls.Add($label)
    $label
}

function Get-StatusPalette {
    param([string]$Status)
    switch ($Status) {
        'PASS' { @('#D8F0E2','#08783F') }
        'VERIFICATION PENDING' { @('#FFE3A1','#875200') }
        'ACTION REQUIRED' { @('#FFC1C1','#A31515') }
        'CHECKING' { @('#CBE6FF','#075AA8') }
        'UNABLE TO DETERMINE' { @('#EADFF4','#674183') }
        default { @('#DCE4EE','#40536D') }
    }
}

function Set-ValidationTheme {
    # Capture existing semantic labels before regrouping controls into cards.
    $concurrentLabel = @($script:form.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Text -eq 'Concurrent checks' })[0]
    $computerLabel = @($script:form.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Text -eq 'Computer status' })[0]
    $searchLabel = @($script:form.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Text -eq 'Search computer' })[0]
    $script:form.SuspendLayout()
    $script:form.BackColor = [Drawing.Color]::FromArgb(239,244,249)
    $script:form.ForeColor = [Drawing.Color]::FromArgb(17,40,75)
    $script:form.Font = [Drawing.Font]::new('Segoe UI',10)
    $title.ForeColor = [Drawing.Color]::FromArgb(10,34,69)
    $title.Font = [Drawing.Font]::new('Segoe UI',22,[Drawing.FontStyle]::Bold)
    $title.SetBounds(24,40,1000,44)
    $script:setupCard = [ValidationUI.Card]::new(); $script:form.Controls.Add($script:setupCard)
    $script:progressCard = [ValidationUI.Card]::new(); $script:form.Controls.Add($script:progressCard)
    $script:resultsCard = [ValidationUI.Card]::new(); $script:form.Controls.Add($script:resultsCard)
    [void](New-ThemeHeading $script:setupCard 'Wave setup')
    [void](New-ThemeHeading $script:progressCard 'Progress and summary')
    $computerLabel.Parent = $script:resultsCard; $computerLabel.SetBounds(20,14,250,28)
    $computerLabel.Font = [Drawing.Font]::new('Segoe UI',13,[Drawing.FontStyle]::Bold)
    $computerLabel.BackColor = [Drawing.Color]::Transparent
    foreach ($path in @($script:inputPath,$script:finishedPath,$script:unfinishedPath)) {
        foreach ($c in @($path.Label,$path.Box,$path.Button)) { $c.Parent = $script:setupCard; $c.Anchor = 'Top,Left' }
        $path.Label.BackColor = [Drawing.Color]::Transparent
        $path.Box.BorderStyle = 'FixedSingle'; $path.Box.BackColor = [Drawing.Color]::FromArgb(253,254,255)
    }
    foreach ($c in @($script:credentialButton,$script:accountLabel,$script:concurrency,$script:loadButton,$script:reassessButton,$script:startButton,$script:stopButton,$concurrentLabel)) {
        $c.Parent = $script:setupCard; $c.Anchor = 'Top,Left'
    }
    $script:accountLabel.BackColor = [Drawing.Color]::Transparent
    $concurrentLabel.BackColor = [Drawing.Color]::Transparent
    $script:startButton.Primary = $true; $script:startButton.Font = [Drawing.Font]::new('Segoe UI',11,[Drawing.FontStyle]::Bold)
    $script:divider = [Windows.Forms.Panel]::new(); $script:divider.BackColor = [Drawing.Color]::FromArgb(219,228,239)
    $script:setupCard.Controls.Add($script:divider)
    foreach ($c in @($script:progress,$script:summary,$script:counts)) { $c.Parent = $script:progressCard; $c.Anchor = 'Top,Left' }
    $script:summary.BackColor = [Drawing.Color]::Transparent; $script:summary.Font = [Drawing.Font]::new('Segoe UI',11)
    $script:counts.Visible = $false
    $script:percentLabel = [Windows.Forms.Label]::new(); $script:percentLabel.BackColor = [Drawing.Color]::Transparent
    $script:percentLabel.Font = [Drawing.Font]::new('Segoe UI',11); $script:percentLabel.Text = '0%'; $script:progressCard.Controls.Add($script:percentLabel)
    $script:badgeFlow = [Windows.Forms.FlowLayoutPanel]::new(); $script:badgeFlow.BackColor = [Drawing.Color]::Transparent
    $script:badgeFlow.WrapContents = $true; $script:progressCard.Controls.Add($script:badgeFlow)
    $script:statusCountLabels = @{}
    foreach ($status in @('PASS','VERIFICATION PENDING','ACTION REQUIRED','NOT READY','UNABLE TO DETERMINE')) {
        $label = [Windows.Forms.Label]::new(); $label.AutoSize = $true
        $label.Font = [Drawing.Font]::new('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
        $label.ForeColor = [Drawing.ColorTranslator]::FromHtml((Get-StatusPalette $status)[1])
        $label.Margin = [Windows.Forms.Padding]::new(0,0,22,0); $label.Text = "0  $status"
        $script:badgeFlow.Controls.Add($label); $script:statusCountLabels[$status] = $label
    }
    foreach ($c in @($script:filter,$script:search,$script:grid,$script:detail,$searchLabel)) {
        $c.Parent = $script:resultsCard; $c.Anchor = 'Top,Left'
    }
    $searchLabel.Text = 'Search'; $searchLabel.BackColor = [Drawing.Color]::Transparent
    $script:filter.FlatStyle = 'Flat'; $script:search.BorderStyle = 'FixedSingle'
    $script:exportButton.Parent = $script:resultsCard; $script:exportButton.Anchor = 'Top,Left'
    $script:detail.BorderStyle = 'None'; $script:detail.BackColor = [Drawing.Color]::FromArgb(241,246,252)
    $script:detail.Font = [Drawing.Font]::new('Segoe UI',9.5)
    $script:grid.BorderStyle = 'None'; $script:grid.EnableHeadersVisualStyles = $false
    $script:grid.CellBorderStyle = 'SingleHorizontal'; $script:grid.GridColor = [Drawing.Color]::FromArgb(224,232,242)
    $script:grid.ColumnHeadersBorderStyle = 'Single'; $script:grid.ColumnHeadersHeightSizeMode = 'DisableResizing'; $script:grid.ColumnHeadersHeight = 36
    $script:grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(244,248,253)
    $script:grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:form.ForeColor
    $script:grid.ColumnHeadersDefaultCellStyle.Font = [Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
    $script:grid.DefaultCellStyle.ForeColor = $script:form.ForeColor
    $script:grid.DefaultCellStyle.SelectionForeColor = $script:form.ForeColor
    $script:grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(225,240,255)
    $script:grid.DefaultCellStyle.Padding = [Windows.Forms.Padding]::new(8,0,4,0)
    $script:grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(250,252,255)
    $script:grid.RowTemplate.Height = 34; $script:grid.AllowUserToResizeRows = $false
    foreach ($row in $script:grid.Rows) { $row.Height = 34 }
    $script:statusFont = [Drawing.Font]::new('Segoe UI',9,[Drawing.FontStyle]::Bold)
    $script:grid.Add_CellPainting({
        param($sender,$e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0 -or $sender.Columns[$e.ColumnIndex].Name -ne 'Status') { return }
        $e.PaintBackground($e.CellBounds,$true)
        $status = [string]$e.FormattedValue; $palette = Get-StatusPalette $status
        $textSize = [Windows.Forms.TextRenderer]::MeasureText($e.Graphics,$status,$script:statusFont)
        $width = [math]::Min($e.CellBounds.Width - 12,$textSize.Width + 16)
        $rect = [Drawing.RectangleF]::new(($e.CellBounds.X + 6),($e.CellBounds.Y + 5),$width,24)
        if ($width -gt 2) {
            $path = [ValidationUI.Shapes]::Round($rect,12)
            $brush = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($palette[0]))
            $previous = $e.Graphics.SmoothingMode
            try {
                $e.Graphics.SmoothingMode = 'AntiAlias'; $e.Graphics.FillPath($brush,$path)
                [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$status,$script:statusFont,[Drawing.Rectangle]::Round($rect),[Drawing.ColorTranslator]::FromHtml($palette[1]),[Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,EndEllipsis')
            }
            finally { $e.Graphics.SmoothingMode = $previous; $path.Dispose(); $brush.Dispose() }
        }
        $e.Handled = $true
    })
    $script:footer.ForeColor = [Drawing.Color]::FromArgb(67,87,115)
    $script:footer.BackColor = [Drawing.Color]::Transparent
    # Store semantic labels for the resize handler; it does not capture temporary
    # local variables through a PowerShell closure.
    $script:themeConcurrentLabel = $concurrentLabel; $script:themeSearchLabel = $searchLabel
    $script:form.MinimumSize = [Drawing.Size]::new(1166,887)
    $script:form.ClientSize = [Drawing.Size]::new(1320,968)
    $script:form.Add_Resize({ Set-ValidationThemeLayout })
    Set-ValidationThemeLayout
    $script:form.ResumeLayout($true)
}

function Set-ValidationThemeLayout {
    $w = $script:form.ClientSize.Width; $h = $script:form.ClientSize.Height; $cw = $w - 36
    $script:setupCard.SetBounds(18,92,$cw,232)
    $split = $cw - 392
    $index = 0
    foreach ($path in @($script:inputPath,$script:finishedPath,$script:unfinishedPath)) {
        $y = 49 + (42 * $index)
        $path.Label.SetBounds(20,($y + 4),182,25)
        $path.Box.SetBounds(205,$y,($split - 325),28)
        $path.Button.SetBounds(($split - 108),($y - 2),92,33)
        $index++
    }
    $script:divider.SetBounds($split,44,1,156)
    $right = $split + 24
    $script:themeConcurrentLabel.SetBounds($right,53,175,26)
    $script:concurrency.SetBounds(($right + 185),49,80,29)
    $script:startButton.SetBounds($right,102,142,47)
    $script:stopButton.SetBounds(($right + 152),102,192,47)
    $script:loadButton.SetBounds($right,164,110,34)
    $script:reassessButton.SetBounds(($right + 120),164,224,34)
    $script:accountLabel.SetBounds(20,184,390,28)
    $script:credentialButton.SetBounds(424,178,155,35)
    $script:progressCard.SetBounds(18,338,$cw,146)
    $progressWidth = [int]($cw * 0.39)
    $script:progress.SetBounds(20,62,$progressWidth,22)
    $script:percentLabel.SetBounds(($progressWidth + 30),60,55,28)
    $script:summary.SetBounds(($progressWidth + 100),59,($cw - $progressWidth - 120),30)
    $script:badgeFlow.SetBounds(20,105,($cw - 40),32)
    $rh = $h - 542
    $script:resultsCard.SetBounds(18,498,$cw,$rh)
    $script:exportButton.SetBounds(($cw - 690),12,110,34)
    $script:filter.SetBounds(($cw - 560),14,220,28)
    $script:themeSearchLabel.SetBounds(($cw - 322),18,60,24)
    $script:search.SetBounds(($cw - 260),14,240,28)
    $script:detail.Visible = $script:app.DetailsVisible
    $tableHeight = if ($script:app.DetailsVisible) { $rh - 166 } else { $rh - 75 }
    $script:grid.SetBounds(14,57,($cw - 28),$tableHeight)
    $script:detail.SetBounds(22,($rh - 96),($cw - 44),80)
    $script:footer.SetBounds(24,($h - 32),($w - 48),26)
}

function Update-ValidationThemeSummary {
    if (-not $script:statusCountLabels) { return }
    foreach ($status in $script:statusCountLabels.Keys) {
        $count = [int]$script:app.StatusCounts[$status]
        $script:statusCountLabels[$status].Text = "$count  $status"
    }
    $total = $script:app.Rows.Count
    $percent = if ($total) { [int][math]::Floor(100 * $script:app.Done / $total) } else { 0 }
    $script:percentLabel.Text = "$percent%"
    $script:progress.AccessibleDescription = "$($script:app.Done) of $total assessed ($percent percent)"
}
