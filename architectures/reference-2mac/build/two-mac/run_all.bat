@echo off
setlocal
cd /d "%~dp0"
call run_xst.bat
if errorlevel 1 exit /b %ERRORLEVEL%
call run_implementation.bat
if errorlevel 1 exit /b %ERRORLEVEL%
echo.
echo ALL AVAILABLE FLOW STEPS COMPLETED. Inspect all reports before claiming timing/resource success.
exit /b 0
