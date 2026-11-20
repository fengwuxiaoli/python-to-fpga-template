#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

cleanup() {
  rm -rf xsim.dir xvlog.* xelab.* xsim.* *.wdb *.jou
}
trap cleanup EXIT
cleanup

VIVADO_BIN="${VIVADO_BIN:-$(dirname "$(command -v vivado)")}"

echo "[1/3] Compiling Canary FIR RTL + testbench with xvlog -sv..."
"$VIVADO_BIN/xvlog" -sv \
  ../rtl/axis_skid.sv \
  ../rtl/canary_fir_regs.sv \
  ../rtl/canary_fir_core.sv \
  ../rtl/canary_fir_top.sv \
  ../tb/tb_canary_fir.sv

echo "[2/3] Elaborating tb_canary_fir with xelab..."
"$VIVADO_BIN/xelab" -debug typical -top tb_canary_fir -snapshot tb_canary_snap

echo "[3/3] Running XSim co-simulation against Stage 1 Python vectors..."
"$VIVADO_BIN/xsim" tb_canary_snap -runall -testplusarg VEC_DIR=../test_vectors
