# Vivado, IPI, XDC & XSDB Reference Recipes

Copy-pasteable patterns verified on AMD Vivado 2026.1 + Zynq UltraScale+ (`xczu9eg`).

---

## 1. Out-of-Tree Build Path Setup (`board_config.tcl`)
Keep Vivado projects out of OneDrive, spaces, and non-ASCII folders (`%TEMP%` default, overridable via `FPGA_BUILD_DIR`):

```tcl
set PART           [expr {[info exists ::env(FPGA_PART)]       && $::env(FPGA_PART)       ne "" ? $::env(FPGA_PART)       : "xczu9eg-ffvb1156-2-e"}]
set BOARD_PART     [expr {[info exists ::env(FPGA_BOARD_PART)] && $::env(FPGA_BOARD_PART) ne "" ? $::env(FPGA_BOARD_PART) : "xilinx.com:zcu102:part0:3.4"}]
set TARGET_CLK_MHZ [expr {[info exists ::env(FPGA_CLK_MHZ)]    && $::env(FPGA_CLK_MHZ)    ne "" ? $::env(FPGA_CLK_MHZ)    : "245.761"}]

set tmp_root [expr {[info exists ::env(TEMP)] && $::env(TEMP) ne "" ? $::env(TEMP) : "/tmp"}]
set BUILD_DIR [expr {[info exists ::env(FPGA_BUILD_DIR)] && $::env(FPGA_BUILD_DIR) ne ""
  ? [file normalize $::env(FPGA_BUILD_DIR)]
  : [file normalize [file join $tmp_root "fpga_build"]]}]
```

---

## 2. Verilog-2001 IPI Wrapper Interface Attributes
Vivado IPI (`create_bd_cell -type module`) requires Verilog-2001 compatible ports and explicit interface attributes for automatic bus inference:

```verilog
module my_block_bd_wrapper #(
  parameter integer DATA_WIDTH = 16
)(
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axil:s_axis:m_axis, ASSOCIATED_RESET rst_n" *)
  input  wire clk,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire rst_n,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axil AWADDR" *)
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
  input  wire [7:0]  s_axil_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axil AWVALID" *)
  input  wire        s_axil_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axil AWREADY" *)
  output wire        s_axil_awready,
  // ... remaining AXI4-Lite channels ...

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
  input  wire [DATA_WIDTH-1:0] s_axis_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
  input  wire                  s_axis_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
  output wire                  s_axis_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)
  input  wire                  s_axis_tlast
);
```

---

## 3. Dynamic `ps8/pl_clk0` Query & Clock Wizard Wiring
Avoid hardcoding `100.0` MHz when ZCU102/custom PS presets run `99.99 MHz`:

```tcl
set pl0_mhz [expr {[get_property CONFIG.FREQ_HZ [get_bd_pins ps8/pl_clk0]] / 1.0e6}]
set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_core]
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ $pl0_mhz \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $TARGET_CLK_MHZ \
  CONFIG.USE_LOCKED {true} \
  CONFIG.USE_RESET {true} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
] $clk_wiz
```

---

## 4. Implementation-Only CDC & High-Fanout Reset XDC
Load async clock groups and high-fanout reset properties ONLY in implementation so OOC synthesis does not emit missing-clock warnings:

```tcl
# In create_bd.tcl:
add_files -fileset constrs_1 -norecurse [list "$script_dir/constraints.xdc" "$script_dir/impl_cdc.xdc"]
set_property USED_IN {implementation} [get_files *impl_cdc.xdc]
```

```xdc
# Inside impl_cdc.xdc:
set_clock_groups -asynchronous \
  -group [get_clocks -of_objects [get_pins -hier *ps8*pl_clk0*]] \
  -group [get_clocks -of_objects [get_pins -hier *clk_wiz*clk_out1*]]

set_property MAX_FANOUT_MODE CLOCK_REGION [get_nets -quiet *rst_core/U0/peripheral_aresetn[0]]
set_property FORCE_MAX_FANOUT 256         [get_nets -quiet *rst_core/U0/peripheral_aresetn[0]]
```

---

## 5. Tiered Checkpoint Build & Fixed XSA Export
```tcl
if {$step eq "synth" || $step eq "all"} {
  reset_run synth_1
  launch_runs synth_1 -jobs $jobs
  wait_on_run synth_1
  open_run synth_1
  write_checkpoint -force "$dcp_dir/post_synth.dcp"
  report_utilization    -file "$rpt_dir/post_synth_util.rpt"
  report_timing_summary -file "$rpt_dir/post_synth_timing.rpt"
}

if {$step eq "impl" || $step eq "bitstream" || $step eq "all"} {
  reset_run impl_1
  launch_runs impl_1 -jobs $jobs
  wait_on_run impl_1
  open_run impl_1
  write_checkpoint -force "$dcp_dir/post_route.dcp"
  report_utilization    -file "$rpt_dir/post_route_util.rpt"
  report_timing_summary -file "$rpt_dir/post_route_timing.rpt"
}

if {$step eq "bitstream" || $step eq "all"} {
  open_run impl_1
  write_bitstream -force "$build_dir/${DESIGN_NAME}.bit"
  write_hw_platform -fixed -include_bit -force -file "$build_dir/${DESIGN_NAME}.xsa"
}
```

---

## 6. XSDB Zynq MPSoC PS-PL Release Sequence (Phase 1 Bring-Up)
Running `fpga -f` alone leaves PS-PL isolation locked. Extract `.bit` + `psu_init.tcl` from `.xsa`, then execute:

```tcl
connect
targets -set -filter {name =~ "*PSU*"}
rst -system
after 500
source psu_init.tcl
psu_init
after 500
fpga -no-revision-check -f design.bit
after 500
catch {psu_post_config}
after 500
psu_ps_pl_isolation_removal
after 500
psu_ps_pl_reset_config
after 500
targets -set -filter {name =~ "*Cortex-A53 #0*"}
rst -processor
# Verify AXI4-Lite liveness right away:
puts [mrd -value 0xA0000000 1]
```
