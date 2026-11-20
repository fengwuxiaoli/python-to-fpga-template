#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

cleanup() {
  rm -rf xsim.dir xvlog.pb xvlog.log
}
trap cleanup EXIT
cleanup

VIVADO_BIN="${VIVADO_BIN:-$(dirname "$(command -v vivado)")}"

echo "[Stage 2B 1/2] Fast xvlog syntax check (SV RTL + Verilog-2001 BD wrapper)..."
"$VIVADO_BIN/xvlog" -sv \
  rtl/axis_skid.sv \
  rtl/canary_fir_regs.sv \
  rtl/canary_fir_core.sv \
  rtl/canary_fir_top.sv
"$VIVADO_BIN/xvlog" vivado/canary_fir_bd_wrapper.v
cleanup

echo "[Stage 2B 2/2] Running Vivado synth_design -lint (top=canary_fir_bd_wrapper)..."
"$VIVADO_BIN/vivado" -mode batch -nojournal -nolog -source vivado/run_lint.tcl
