#requires -Version 5.1
<#
.SYNOPSIS
    Converts the approved Patch Checkpoint artwork into distribution assets.
.DESCRIPTION
    Uses built-in System.Drawing to resize the approved PNG into a multi-image
    Windows ICO and a 1280x640 GitHub social-preview JPEG. No network access or
    external image tools are required. Run after changing the source artwork.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = Split-Path $PSScriptRoot -Parent
$repositoryRoot = Split-Path $appRoot -Parent
$iconSource = [Drawing.Image]::FromFile((Join-Path $appRoot 'assets\PatchCheckpoint.png'))
$bannerSource = [Drawing.Image]::FromFile((Join-Path $repositoryRoot 'docs\images\patch-checkpoint-brand.png'))
try {
    # PNG-compressed ICO frames preserve alpha and support Explorer's large icons.
    $frames = @(
        foreach ($size in @(16,24,32,48,64,128,256)) {
            $bitmap = [Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            $buffer = [IO.MemoryStream]::new()
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($iconSource,0,0,$size,$size)
                $bitmap.Save($buffer,[Drawing.Imaging.ImageFormat]::Png)
                [pscustomobject]@{ Size = $size; Bytes = $buffer.ToArray() }
            }
            finally { $graphics.Dispose(); $bitmap.Dispose(); $buffer.Dispose() }
        }
    )
    $iconPath = Join-Path $appRoot 'assets\PatchCheckpoint.ico'
    $writer = [IO.BinaryWriter]::new([IO.File]::Create($iconPath))
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
        $offset = 6 + (16 * $frames.Count)
        foreach ($frame in $frames) {
            $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
    }
    finally { $writer.Dispose() }

    # GitHub's social image uses a compact 2:1 JPEG; retain the full approved banner.
    $banner = [Drawing.Bitmap]::new(1280,640)
    $graphics = [Drawing.Graphics]::FromImage($banner)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($bannerSource,0,0,1280,640)
        $banner.Save((Join-Path $repositoryRoot 'docs\images\patch-checkpoint-social.jpg'),[Drawing.Imaging.ImageFormat]::Jpeg)
    }
    finally { $graphics.Dispose(); $banner.Dispose() }
    Get-Item -LiteralPath $iconPath
}
finally { $iconSource.Dispose(); $bannerSource.Dispose() }
