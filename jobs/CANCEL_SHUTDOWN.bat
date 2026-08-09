@echo off
REM FactorOS: cancel idle-watchdog shutdown (double-click friendly)
REM Usage: CANCEL_SHUTDOWN.bat [/nopause]
set JOBS=D:\FactorOS_Data\jobs
shutdown /a >nul 2>&1
if not exist "%JOBS%" mkdir "%JOBS%"
del /f /q "%JOBS%\shutdown_pending.json" 2>nul
echo cancelled %date% %time%> "%JOBS%\shutdown_cancel.flag"
echo keepalive %date% %time%> "%JOBS%\keepalive"
echo.
echo [FactorOS] Shutdown cancelled. Keepalive touched.
if /I "%~1"=="/nopause" exit /b 0
echo You can close this window.
timeout /t 5 >nul
exit /b 0
