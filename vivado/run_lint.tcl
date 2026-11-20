# ==============================================================================
# Stage 2B: Fast Static RTL Lint Check (Vivado synth_design -lint)
# Checks both SystemVerilog RTL and the Verilog-2001 IPI wrapper in ~15-60 s.
# Usage:
#   vivado -mode batch -nojournal -nolog -source vivado/run_lint.tcl
# ==============================================================================
set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/board_config.tcl"

set lint_dir "$BUILD_DIR/lint"
file mkdir $lint_dir
cd $lint_dir

create_project -in_memory -part $PART
read_verilog -sv $RTL_FILES
read_verilog [list $BD_WRAPPER_FILE]

synth_design -lint -top canary_fir_bd_wrapper -part $PART
puts "=== STAGE 2B LINT COMPLETE (top=canary_fir_bd_wrapper, part=$PART) ==="
exit
