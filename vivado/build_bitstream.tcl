# ==============================================================================
# Stage 2E-2 -> 2E-3 -> 2F: Tiered Checkpoint Build Script (Lessons L9, L12, L13)
# Usage:
#   vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs synth
#   vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs impl
#   vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs bitstream
#   vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs all
# ==============================================================================
set step "synth"
if {$argc >= 1} {
  set step [lindex $argv 0]
}

set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/board_config.tcl"

set xpr_file "$BUILD_DIR/${DESIGN_NAME}.xpr"
set rpt_dir  "$BUILD_DIR/reports"
set dcp_dir  "$BUILD_DIR/checkpoints"

file mkdir $rpt_dir
file mkdir $dcp_dir

if {![file exists $xpr_file]} {
  puts "INFO: Project $xpr_file not found; invoking create_bd.tcl..."
  set ::CANARY_SOURCED_FROM_BUILD 1
  source "$script_dir/create_bd.tcl"
  unset ::CANARY_SOURCED_FROM_BUILD
} else {
  open_project $xpr_file
}

set jobs 4
if {[info exists ::env(NUMBER_OF_PROCESSORS)]} {
  set jobs [expr {min(8, $::env(NUMBER_OF_PROCESSORS))}]
}

if {$step eq "synth" || $step eq "all"} {
  puts "=== STAGE 2E-2: Launching Top Synthesis (jobs=$jobs) ==="
  reset_run synth_1
  launch_runs synth_1 -jobs $jobs
  wait_on_run synth_1
  if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed! Inspect runme.log in $BUILD_DIR/${DESIGN_NAME}.runs/synth_1"
  }
  open_run synth_1
  write_checkpoint      -force "$dcp_dir/post_synth.dcp"
  report_utilization    -file  "$rpt_dir/post_synth_util.rpt"
  report_timing_summary -file  "$rpt_dir/post_synth_timing.rpt"
}

if {$step eq "impl" || $step eq "bitstream" || $step eq "all"} {
  puts "=== STAGE 2E-3: Launching Implementation (opt/place/route, jobs=$jobs) ==="
  reset_run impl_1
  launch_runs impl_1 -jobs $jobs
  wait_on_run impl_1
  if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed! Inspect runme.log in $BUILD_DIR/${DESIGN_NAME}.runs/impl_1"
  }
  open_run impl_1
  write_checkpoint      -force "$dcp_dir/post_route.dcp"
  report_utilization    -file  "$rpt_dir/post_route_util.rpt"
  report_timing_summary -file  "$rpt_dir/post_route_timing.rpt"

  set wns [get_property STATS.WNS [get_runs impl_1]]
  set tns [get_property STATS.TNS [get_runs impl_1]]
  set whs [get_property STATS.WHS [get_runs impl_1]]
  puts "INFO: Post-Route WNS=$wns ns, TNS=$tns ns, WHS=$whs ns"
  if {$wns < 0.0 || $whs < 0.0} {
    error "Timing closure failed (WNS=$wns, WHS=$whs)! Fix constraints or RTL before bitstream."
  }
}

if {$step eq "bitstream" || $step eq "all"} {
  puts "=== STAGE 2F: Generating Bitstream & Fixed XSA Hardware Platform ==="
  open_run impl_1
  write_bitstream -force "$BUILD_DIR/${DESIGN_NAME}.bit"
  write_hw_platform -fixed -include_bit -force -file "$BUILD_DIR/${DESIGN_NAME}.xsa"
  puts "INFO: Generated $BUILD_DIR/${DESIGN_NAME}.bit and $BUILD_DIR/${DESIGN_NAME}.xsa"
}

close_project
exit
