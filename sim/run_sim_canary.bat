@echo off
setlocal
REM ============================================================================
REM Stage 2C: Vivado XSim Unit Co-Simulation for Canary FIR
REM Requires Python golden vectors (`py python/generate_canary_vectors.py`).
REM ============================================================================
pushd "%~dp0"
if "%VIVADO_BIN%"=="" set "VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin"

if exist xsim.dir\tb_canary_snap rmdir /s /q xsim.dir\tb_canary_snap
del /q xvlog.* xelab.* xsim.* *.wdb *.jou 2>nul

echo [1/3] Compiling Canary FIR RTL + testbench with xvlog -sv...
call "%VIVADO_BIN%\xvlog.bat" -sv ^
  ..\rtl\axis_skid.sv ^
  ..\rtl\canary_fir_regs.sv ^
  ..\rtl\canary_fir_core.sv ^
  ..\rtl\canary_fir_top.sv ^
  ..\tb\tb_canary_fir.sv
if %ERRORLEVEL% neq 0 (
  echo ERROR: xvlog compilation failed!
  set "RC=1"
  goto :cleanup
)

echo [2/3] Elaborating tb_canary_fir with xelab...
call "%VIVADO_BIN%\xelab.bat" -debug typical -top tb_canary_fir -snapshot tb_canary_snap
if %ERRORLEVEL% neq 0 (
  echo ERROR: xelab elaboration failed!
  set "RC=1"
  goto :cleanup
)
if not exist xsim.dir\tb_canary_snap\xsimk.exe (
  echo ERROR: xsimk.exe missing after xelab - silent elaboration failure!
  set "RC=1"
  goto :cleanup
)

echo [3/3] Running XSim co-simulation against Stage 1 Python vectors...
call "%VIVADO_BIN%\xsim.bat" tb_canary_snap -runall -testplusarg "VEC_DIR=../test_vectors"
set "RC=%ERRORLEVEL%"

:cleanup
if exist xsim.dir rmdir /s /q xsim.dir
del /q xvlog.* xelab.* xsim.* *.wdb *.jou 2>nul
popd
exit /b %RC%
