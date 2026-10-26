@echo off
setlocal
cd /d "%~dp0"
echo === XST synthesis: parallel_4mac_base ===
where xst >nul 2>nul
if errorlevel 1 (
  echo ERROR: xst.exe was not found. Run this from an Xilinx ISE 14.7 Command Prompt.
  exit /b 9009
)
xst -ifn parallel_4mac_base.xst -ofn parallel_4mac_base.syr
set RC=%ERRORLEVEL%
echo XST exit code: %RC%
echo Inspect parallel_4mac_base.syr and the generated parallel_4mac_base.ngc before continuing.
exit /b %RC%
