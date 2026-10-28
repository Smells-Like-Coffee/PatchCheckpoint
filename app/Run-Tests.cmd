@echo off
rem Run deterministic offline logic tests; no remote queries or scans are performed.
set "ValidationPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "ValidationPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%ValidationPowerShell%" -NoProfile -File "%~dp0Test-Offline.ps1"
if errorlevel 1 goto failed
"%ValidationPowerShell%" -NoProfile -File "%~dp0Test-RemoteLogic.ps1"
if errorlevel 1 goto failed
echo Offline logic tests passed.
pause
exit /b 0
:failed
echo Offline tests failed. Review the error above.
pause
exit /b 1
