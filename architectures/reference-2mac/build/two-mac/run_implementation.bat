@echo off
setlocal EnableExtensions
set "PRJ_NAME=two_mac_2x8x1"
set "DEVICE=xc3s400-4-pq208"
set "RUN_DIR=%~dp0"
for %%I in ("%~dp0..\..") do set "ROOT_DIR=%%~fI"
set "OUT_DIR=%RUN_DIR%implementation_output"

echo ============================================================
echo ISE 14.7 implementation flow: %PRJ_NAME%
echo Target: %DEVICE%
echo Output: %OUT_DIR%
echo ============================================================

where ngdbuild.exe >nul 2>nul
if errorlevel 1 (echo ERROR: ngdbuild.exe not found. Open ISE Design Suite Command Prompt.& exit /b 9009)
where map.exe >nul 2>nul
if errorlevel 1 (echo ERROR: map.exe not found. Open ISE Design Suite Command Prompt.& exit /b 9009)
where par.exe >nul 2>nul
if errorlevel 1 (echo ERROR: par.exe not found. Open ISE Design Suite Command Prompt.& exit /b 9009)
where trce.exe >nul 2>nul
if errorlevel 1 (echo ERROR: trce.exe not found. Open ISE Design Suite Command Prompt.& exit /b 9009)
if not exist "%RUN_DIR%%PRJ_NAME%.ngc" (echo ERROR: %PRJ_NAME%.ngc not found. Run run_xst.bat first.& exit /b 2)
if not exist "%ROOT_DIR%\constraints\reference_clock_20ns.ucf" (echo ERROR: reference_clock_20ns.ucf not found.& exit /b 2)
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
copy /Y "%RUN_DIR%%PRJ_NAME%.ngc" "%OUT_DIR%\%PRJ_NAME%.ngc" >nul
if errorlevel 1 (echo ERROR copying NGC.& exit /b 3)
pushd "%OUT_DIR%"

echo [1/4] Translate with NGDBuild...
ngdbuild.exe -dd _ngo -nt timestamp -uc "%ROOT_DIR%\constraints\reference_clock_20ns.ucf" -p %DEVICE% "%PRJ_NAME%.ngc" "%PRJ_NAME%.ngd"
if errorlevel 1 (echo ERROR: NGDBuild failed. Inspect %PRJ_NAME%.bld.& popd & exit /b 10)

echo [2/4] Map...
map.exe -p %DEVICE% -w -o "%PRJ_NAME%_map.ncd" "%PRJ_NAME%.ngd" "%PRJ_NAME%.pcf"
if errorlevel 1 (echo ERROR: MAP failed. Inspect %PRJ_NAME%_map.mrp.& popd & exit /b 11)

echo [3/4] Place and Route...
par.exe -w "%PRJ_NAME%_map.ncd" "%PRJ_NAME%.ncd" "%PRJ_NAME%.pcf"
if errorlevel 1 (echo ERROR: PAR failed. Inspect %PRJ_NAME%.par.& popd & exit /b 12)

echo [4/4] Timing analysis with TRACE...
trce.exe -v 10 -u 10 -fastpaths -o "%PRJ_NAME%.twr" "%PRJ_NAME%.ncd" "%PRJ_NAME%.pcf"
if errorlevel 1 (echo ERROR: TRACE failed. Inspect %PRJ_NAME%.twr and console output.& popd & exit /b 13)

echo.
echo IMPLEMENTATION FLOW COMPLETED.
echo Keep these reports: %PRJ_NAME%.bld, %PRJ_NAME%_map.mrp, %PRJ_NAME%.par, %PRJ_NAME%.twr
echo reports location: %OUT_DIR%
echo Do NOT generate a bitstream or program hardware: LOC pin constraints are unavailable.
popd
exit /b 0
