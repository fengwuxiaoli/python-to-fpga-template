# ==============================================================================
# Stage 2E-1: Out-of-Context (OOC) Block Resource & Timing Budget Check
# Runs in-memory synthesis on `canary_fir_top` at TARGET_CLK_MHZ (~30-60 s)
# to verify SRL/DSP inference and Fmax before slow IPI/P&R integration.
# Usage:
#   vivado -mode batch -nojournal -nolog -source vivado/run_ooc_synth.tcl
# ==============================================================================
set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/board_config.tcl"

set rpt_dir "$BUILD_DIR/reports"
set ooc_dir "$BUILD_DIR/ooc_tmp"
file mkdir $rpt_dir
file mkdir $ooc_dir
cd $ooc_dir

create_project -in_memory -part $PART
read_verilog -sv $RTL_FILES

synth_design -top canary_fir_top -part $PART -mode out_of_context

set clk_period_ns [expr {1000.0 / double($TARGET_CLK_MHZ)}]
create_clock -period $clk_period_ns -name clk [get_ports clk]

report_utilization    -file "$rpt_dir/ooc_util.rpt"
report_timing_summary -file "$rpt_dir/ooc_timing.rpt"

set setup_paths [get_timing_paths -max_paths 1 -nworst 1 -setup]
set wns [expr {[llength $setup_paths] > 0 ? [get_property SLACK [lindex $setup_paths 0]] : "N/A"}]

set lut_cnt [llength [get_cells -quiet -hier -filter {PRIMITIVE_SUBGROUP == LUT}]]
set ff_cnt  [llength [get_cells -quiet -hier -filter {PRIMITIVE_GROUP == REGISTER || PRIMITIVE_GROUP == FLOP_LATCH}]]
set dsp_cnt [llength [get_cells -quiet -hier -filter {REF_NAME =~ DSP48* || REF_NAME =~ DSP58*}]]
set srl_cnt [llength [get_cells -quiet -hier -filter {PRIMITIVE_SUBGROUP == SRL}]]

puts [format "=== STAGE 2E-1 OOC SUMMARY (%s @ %.3f MHz, T=%.3f ns) ===" $PART $TARGET_CLK_MHZ $clk_period_ns]
puts [format "  OOC Setup WNS : %s ns" $wns]
puts [format "  Cells         : LUT=%d  FF=%d  DSP=%d  SRL=%d" $lut_cnt $ff_cnt $dsp_cnt $srl_cnt]
puts "  Reports       : $rpt_dir/ooc_util.rpt, $rpt_dir/ooc_timing.rpt"
exit
