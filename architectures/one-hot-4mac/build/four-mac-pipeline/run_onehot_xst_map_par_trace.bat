@echo off
setlocal EnableExtensions
rem Run inside Xilinx ISE 14.7 Design Suite Command Prompt.
rem Output is an unvalidated timing experiment, not a board timing claim.
set "RUN_DIR=%~dp0"
call "%RUN_DIR%run_xst.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%RUN_DIR%run_implementation.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
pushd "%RUN_DIR%implementation_output"
trce.exe -v 20 -u 20 -o pipe_onehot_verbose.twr parallel_4mac_pipe.ncd parallel_4mac_pipe.pcf
if errorlevel 1 (popd & exit /b 13)
popd
echo DONE: inspect implementation_output\pipe_onehot_verbose.twr
exit /b 0
