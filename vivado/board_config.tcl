# ==============================================================================
# Centralized Board, Clock & Out-of-Tree Build Path Configuration
# Override any setting via environment variables before running Vivado scripts:
#   FPGA_PART       (default: xczu9eg-ffvb1156-2-e)
#   FPGA_BOARD_PART (default: xilinx.com:zcu102:part0:3.4)
#   FPGA_CLK_MHZ    (default: 245.761)
#   FPGA_BUILD_DIR  (default: %TEMP%/python_to_fpga_canary or /tmp/...)
# ==============================================================================
set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/.."]
set rtl_dir    "$repo_dir/rtl"

set DESIGN_NAME "canary_fir"
set BD_NAME     "${DESIGN_NAME}_bd"

set PART [expr {[info exists ::env(FPGA_PART)] && $::env(FPGA_PART) ne ""
  ? $::env(FPGA_PART)
  : "xczu9eg-ffvb1156-2-e"}]

set BOARD_PART [expr {[info exists ::env(FPGA_BOARD_PART)]
  ? $::env(FPGA_BOARD_PART)
  : "xilinx.com:zcu102:part0:3.4"}]

set TARGET_CLK_MHZ [expr {[info exists ::env(FPGA_CLK_MHZ)] && $::env(FPGA_CLK_MHZ) ne ""
  ? $::env(FPGA_CLK_MHZ)
  : "245.761"}]

set tmp_root [expr {[info exists ::env(TEMP)] && $::env(TEMP) ne "" ? $::env(TEMP) : "/tmp"}]
if {[info exists ::env(FPGA_BUILD_DIR)] && $::env(FPGA_BUILD_DIR) ne ""} {
  set BUILD_DIR [file normalize $::env(FPGA_BUILD_DIR)]
} else {
  set BUILD_DIR [file normalize [file join $tmp_root "python_to_fpga_canary"]]
}

set RTL_FILES [list \
  "$rtl_dir/axis_skid.sv" \
  "$rtl_dir/canary_fir_regs.sv" \
  "$rtl_dir/canary_fir_core.sv" \
  "$rtl_dir/canary_fir_top.sv" \
]

set BD_WRAPPER_FILE "$script_dir/canary_fir_bd_wrapper.v"
