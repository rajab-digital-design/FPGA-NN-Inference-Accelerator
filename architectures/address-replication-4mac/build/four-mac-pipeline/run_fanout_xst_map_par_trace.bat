@echo off
setlocal EnableExtensions
set "RUN_DIR=%~dp0"
call "%RUN_DIR%run_xst.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%RUN_DIR%run_implementation.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
pushd "%RUN_DIR%implementation_output"
trce.exe -v 20 -u 20 -o pipe_fanout_verbose.twr parallel_4mac_pipe.ncd parallel_4mac_pipe.pcf
if errorlevel 1 (popd & exit /b 13)
popd
echo DONE: inspect the generated .syr, .mrp, .par and pipe_fanout_verbose.twr
exit /b 0
