#requires -Version 5.1
<#
.SYNOPSIS
    Builds the x64 Patch Checkpoint executable from local reviewed sources.
.DESCRIPTION
    Uses the Windows .NET Framework C# compiler and Windows PowerShell 5.1 assembly.
    Embeds the application and its help files; downloads nothing and changes no
    execution policy. Produces an unsigned Windows executable with no elevation.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) { throw 'Build using x64 Windows PowerShell 5.1.' }
$appRoot = Split-Path $PSScriptRoot -Parent
$repositoryRoot = Split-Path $appRoot -Parent
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not [IO.File]::Exists($compiler)) { throw 'Windows .NET Framework C# compiler is unavailable.' }
$output = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($output) -ne '.exe') { throw 'OutputPath must end in .exe.' }
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
if ([IO.File]::Exists($output)) { throw 'Choose a new output filename; builds never replace an existing executable.' }
$arguments = @('/nologo','/target:winexe','/platform:x64','/optimize+','/debug-',('/out:' + $output),('/reference:' + [PowerShell].Assembly.Location),'/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll')
# Older in-box compilers do not expose /deterministic. The reviewed source and
# SHA256 manifest remain the reproducibility record for the distributed build.
foreach ($name in @('Start-PatchCheckpoint.ps1','Validation.Core.ps1','Remote.Assessment.ps1','UI.Theme.ps1','UI.Commands.ps1','Diagnostics.Export.ps1','Computers.example.csv')) {
    $arguments += '/resource:' + (Join-Path $appRoot $name) + ',PatchCheckpoint.' + $name
}
foreach ($name in @('README.md','USER-GUIDE.md','TROUBLESHOOTING.md','CHANGELOG.md','SECURITY.md')) {
    $arguments += '/resource:' + (Join-Path $repositoryRoot $name) + ',PatchCheckpoint.' + $name
}
$arguments += '/resource:' + (Join-Path $PSScriptRoot 'Executable.SmokeTest.ps1') + ',PatchCheckpoint.Executable.SmokeTest.ps1'
$arguments += Join-Path $PSScriptRoot 'PatchCheckpointHost.cs'
& $compiler @arguments
if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($output)) { throw 'Executable compilation failed.' }
Get-Item -LiteralPath $output | Select-Object FullName,Length
Get-FileHash -LiteralPath $output -Algorithm SHA256
