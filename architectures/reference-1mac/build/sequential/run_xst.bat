@echo off
setlocal
cd /d "%~dp0"
echo === XST synthesis: sequential_1mac ===
where xst >nul 2>nul
if errorlevel 1 (
  echo ERROR: xst.exe was not found. Run this from an Xilinx ISE 14.7 Command Prompt.
  exit /b 9009
)
xst -ifn sequential_1mac.xst -ofn sequential_1mac.syr
set RC=%ERRORLEVEL%
echo XST exit code: %RC%
echo Inspect sequential_1mac.syr and the generated sequential_1mac.ngc before continuing.
exit /b %RC%
