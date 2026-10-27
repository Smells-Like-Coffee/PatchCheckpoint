@echo off
rem Launch the GUI with 64-bit Windows PowerShell; honor organizational execution policy.
set "ValidationPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "ValidationPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%ValidationPowerShell%" -NoProfile -STA -File "%~dp0Start-ServerUpdateValidation.ps1" %*
if errorlevel 1 pause
