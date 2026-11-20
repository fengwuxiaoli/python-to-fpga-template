@echo off
setlocal
REM ============================================================================
REM Stage 2B: Fast Static RTL Lint Check (xvlog -sv + Vivado synth_design -lint)
REM ============================================================================
pushd "%~dp0\.."
if "%VIVADO_BIN%"=="" set "VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin"
set "PATH=%VIVADO_BIN%;%PATH%"

if exist xsim.dir rmdir /s /q xsim.dir
del /q xvlog.pb xvlog.log 2>nul

echo [Stage 2B 1/2] Fast xvlog syntax check (SV RTL + Verilog-2001 BD wrapper)...
call "%VIVADO_BIN%\xvlog.bat" -sv ^
  "rtl\axis_skid.sv" ^
  "rtl\canary_fir_regs.sv" ^
  "rtl\canary_fir_core.sv" ^
  "rtl\canary_fir_top.sv"
if %ERRORLEVEL% neq 0 (
  echo [ERROR] xvlog SystemVerilog check failed!
  set "RC=%ERRORLEVEL%"
  goto :cleanup
)

call "%VIVADO_BIN%\xvlog.bat" ^
  "vivado\canary_fir_bd_wrapper.v"
if %ERRORLEVEL% neq 0 (
  echo [ERROR] xvlog Verilog-2001 wrapper check failed!
  set "RC=%ERRORLEVEL%"
  goto :cleanup
)

if exist xsim.dir rmdir /s /q xsim.dir
del /q xvlog.pb xvlog.log 2>nul

echo [Stage 2B 2/2] Running Vivado synth_design -lint (top=canary_fir_bd_wrapper)...
call "%VIVADO_BIN%\vivado.bat" -mode batch -nojournal -nolog -source "vivado\run_lint.tcl"
set "RC=%ERRORLEVEL%"

:cleanup
if exist xsim.dir rmdir /s /q xsim.dir
del /q xvlog.pb xvlog.log 2>nul
popd
exit /b %RC%
