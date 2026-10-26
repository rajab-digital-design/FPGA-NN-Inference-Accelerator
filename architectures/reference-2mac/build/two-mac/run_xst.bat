@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo XST synthesis: two_mac_2x8x1
echo Target: xc3s400-4-pq208
echo ============================================================
where xst.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: xst.exe was not found. Run this from an Xilinx ISE 14.7 Command Prompt.
  exit /b 9009
)
xst.exe -ifn two_mac_2x8x1.xst -ofn two_mac_2x8x1.syr
set RC=%ERRORLEVEL%
echo XST exit code: %RC%
echo Review two_mac_2x8x1.syr and verify two_mac_2x8x1.ngc exists.
if not "%RC%"=="0" exit /b %RC%
if not exist two_mac_2x8x1.ngc (
  echo ERROR: XST returned success but the NGC file was not found.
  exit /b 2
)
echo XST SYNTHESIS COMPLETED.
exit /b 0
