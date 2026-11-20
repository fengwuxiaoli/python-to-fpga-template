# ==============================================================================
# Stage 2F XSDB JTAG Bring-Up & AXI4-Lite Verification Script (Lesson L13)
# ==============================================================================
# Usage:
#   xsdb bringup/jtag_bringup.tcl [xsa_or_bit_path] [base_addr]
#
# Environment Variables:
#   HW_SERVER_URL : Optional remote hw_server URL (e.g. "TCP:192.168.1.50:3121")
#   SKIP_PSU_INIT : Set "1" if PS is already initialized (e.g. U-Boot/Linux running)
# ==============================================================================

set tmp_root [expr {[info exists ::env(TEMP)] && $::env(TEMP) ne "" ? $::env(TEMP) : "/tmp"}]
set default_xsa [file join [pwd] "canary_fir.xsa"]
if {![file exists $default_xsa] && [info exists ::env(FPGA_BUILD_DIR)] && $::env(FPGA_BUILD_DIR) ne ""} {
  set env_xsa [file join $::env(FPGA_BUILD_DIR) "canary_fir.xsa"]
  if {[file exists $env_xsa]} { set default_xsa $env_xsa }
}
if {![file exists $default_xsa]} {
  set tmp_xsa [file join $tmp_root "python_to_fpga_canary" "canary_fir.xsa"]
  if {[file exists $tmp_xsa]} { set default_xsa $tmp_xsa }
}

set input_path $default_xsa
set BASE_ADDR  0xA0000000

if {$argc >= 1 && [lindex $argv 0] ne ""} { set input_path [file normalize [lindex $argv 0]] }
if {$argc >= 2 && [lindex $argv 1] ne ""} { set BASE_ADDR [expr {[lindex $argv 1]}] }

if {![file exists $input_path]} {
  error "Input file not found: $input_path\nPass path to canary_fir.xsa or canary_fir.bit as arg 1."
}

set skip_psu_init 0
if {[info exists ::env(SKIP_PSU_INIT)] && $::env(SKIP_PSU_INIT) eq "1"} {
  set skip_psu_init 1
}

set bit_file ""
set psu_tcl  ""

if {[string tolower [file extension $input_path]] eq ".xsa"} {
  set work_dir [file join $tmp_root "canary_fir_jtag_work"]
  file mkdir $work_dir
  puts "INFO: Extracting .bit and psu_init.tcl from $input_path -> $work_dir"

  set extracted 0
  if {![catch {exec tar -xf $input_path -C $work_dir canary_fir.bit psu_init.tcl} err]} {
    set extracted 1
  } elseif {![catch {exec unzip -oq $input_path canary_fir.bit psu_init.tcl -d $work_dir} err2]} {
    set extracted 1
  }
  if {!$extracted} {
    error "Failed to extract XSA via tar or unzip: $err"
  }
  set bit_file [file join $work_dir "canary_fir.bit"]
  set psu_tcl  [file join $work_dir "psu_init.tcl"]
} elseif {[string tolower [file extension $input_path]] eq ".bit"} {
  set bit_file $input_path
  set psu_tcl  [file join [file dirname $input_path] "psu_init.tcl"]
} else {
  error "Unsupported file extension '$input_path' (expected .xsa or .bit)."
}

if {![file exists $bit_file]} { error "Bitstream not found: $bit_file" }
if {!$skip_psu_init && ![file exists $psu_tcl]} {
  error "psu_init.tcl not found alongside bitstream ($psu_tcl). Pass .xsa or set SKIP_PSU_INIT=1."
}

proc axi_rd {addr} {
  return [expr {[lindex [mrd -value $addr 1] 0] & 0xFFFFFFFF}]
}

proc axi_wr {addr val} {
  mwr $addr [expr {$val & 0xFFFFFFFF}]
}

proc fmt32 {val} {
  return [format "0x%08X" [expr {$val & 0xFFFFFFFF}]]
}

# Connect to hw_server
if {[info exists ::env(HW_SERVER_URL)] && $::env(HW_SERVER_URL) ne ""} {
  connect -url $::env(HW_SERVER_URL)
} else {
  connect
}
after 300
puts "INFO: Available JTAG targets:\n[targets]"

if {!$skip_psu_init} {
  puts "INFO: Resetting PSU and running psu_init..."
  targets -set -filter {name =~ "*PSU*"}
  rst -system
  after 500
  source $psu_tcl
  psu_init
  after 500
}

puts "INFO: Programming PL with $bit_file ..."
fpga -no-revision-check -f $bit_file
after 500

if {!$skip_psu_init} {
  puts "INFO: Releasing PS-PL isolation bridges (Lesson L13)..."
  if {[catch {psu_post_config} post_err]} {
    puts "WARN: psu_post_config returned '$post_err'; continuing."
  }
  after 500
  psu_ps_pl_isolation_removal
  after 500
  psu_ps_pl_reset_config
  after 500
}

targets -set -filter {name =~ "*Cortex-A53 #0*"}
if {!$skip_psu_init} {
  rst -processor
  after 200
}

puts "\n=== Phase 1 AXI4-Lite Liveness Verification (Base [fmt32 $BASE_ADDR]) ==="
set ver [axi_rd [expr {$BASE_ADDR + 0x00}]]
puts [format "  VERSION (0x00) = %s (Expected: 0x46495231 \"FIR1\")" [fmt32 $ver]]
if {$ver != 0x46495231} {
  error "VERSION mismatch! Check JTAG boot mode switches, clk_wiz lock, and PS-PL isolation."
}

axi_wr [expr {$BASE_ADDR + 0x04}] 0x00000001
set ctrl_one [axi_rd [expr {$BASE_ADDR + 0x04}]]
axi_wr [expr {$BASE_ADDR + 0x04}] 0x00000000
set ctrl_zero [axi_rd [expr {$BASE_ADDR + 0x04}]]
set status_val [axi_rd [expr {$BASE_ADDR + 0x08}]]
set coeff7_val [axi_rd [expr {$BASE_ADDR + 0x2C}]]

puts [format "  CTRL write/read toggle : 1->%s, 0->%s" [fmt32 $ctrl_one] [fmt32 $ctrl_zero]]
puts [format "  STATUS (0x08)          : %s" [fmt32 $status_val]]
puts [format "  COEFF[7] (0x2C)        : %s (Expected: 0x00001923 = 6435)" [fmt32 $coeff7_val]]

if {$ctrl_one != 1 || $ctrl_zero != 0 || $coeff7_val != 6435} {
  error "AXI4-Lite register read/write check failed!"
}

puts "\n=== PHASE 1 JTAG BRING-UP PASSED ==="
exit
