# ==============================================================================
# Stage 2E-2: Parameterized Zynq UltraScale+ Block Design Generator
# Builds PS + Dynamic ClkWiz + SmartConnect + AXI DMA Loopback + `canary_fir`
# into out-of-tree `$BUILD_DIR` (Lessons L9, L10, L11).
#
# Usage:
#   vivado -mode batch -nojournal -nolog -source vivado/create_bd.tcl
# ==============================================================================
set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/board_config.tcl"

file mkdir $BUILD_DIR
cd $BUILD_DIR

create_project -force $DESIGN_NAME $BUILD_DIR -part $PART
if {$BOARD_PART ne ""} {
  set_property board_part $BOARD_PART [current_project]
}

# 1. Register SystemVerilog RTL, Verilog-2001 IPI Wrapper, and Constraints
set all_src $RTL_FILES
lappend all_src $BD_WRAPPER_FILE
add_files -norecurse $all_src
add_files -fileset constrs_1 -norecurse [list "$script_dir/constraints.xdc" "$script_dir/impl_cdc.xdc"]
set_property USED_IN {implementation} [get_files *impl_cdc.xdc]
update_compile_order -fileset sources_1

# 2. Construct Block Design (`canary_fir_bd`)
create_bd_design $BD_NAME

set ps8 [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps8]
if {$BOARD_PART ne ""} {
  apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps8
}
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
  CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
  CONFIG.PSU__USE__S_AXI_GP2 {1} \
  CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
] $ps8

# Lesson L11: Query actual PS clock frequency dynamically instead of hardcoding 100 MHz
set pl0_mhz [expr {[get_property CONFIG.FREQ_HZ [get_bd_pins ps8/pl_clk0]] / 1.0e6}]
set clk_wiz_core [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_core]
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ $pl0_mhz \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $TARGET_CLK_MHZ \
  CONFIG.USE_LOCKED {true} \
  CONFIG.USE_RESET {true} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
] $clk_wiz_core

set rst_core [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_core]

connect_bd_net [get_bd_pins ps8/pl_clk0]           [get_bd_pins clk_wiz_core/clk_in1]
connect_bd_net [get_bd_pins ps8/pl_resetn0]        [get_bd_pins clk_wiz_core/resetn]
connect_bd_net [get_bd_pins ps8/pl_resetn0]        [get_bd_pins rst_core/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_core/clk_out1] [get_bd_pins rst_core/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_core/locked]   [get_bd_pins rst_core/dcm_locked]
connect_bd_net [get_bd_pins clk_wiz_core/clk_out1] [get_bd_pins ps8/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins clk_wiz_core/clk_out1] [get_bd_pins ps8/saxihp0_fpd_aclk]

# Instantiate Verilog-2001 IPI wrapper (Lesson L10) & AXI DMA for PS loopback tests
set fir_core [create_bd_cell -type module -reference canary_fir_bd_wrapper fir_core]

set axi_dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma]
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_sg_include_stscntrl_strm {0} \
  CONFIG.c_m_axi_mm2s_data_width {32} \
  CONFIG.c_m_axis_mm2s_tdata_width {16} \
  CONFIG.c_m_axi_s2mm_data_width {32} \
  CONFIG.c_s_axis_s2mm_tdata_width {16} \
] $axi_dma

# Control SmartConnect (PS M_AXI_HPM0_FPD -> fir_core/s_axil + axi_dma/S_AXI_LITE)
set axi_sc_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_sc_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2} CONFIG.NUM_CLKS {1}] $axi_sc_ctrl

# Data SmartConnect (axi_dma MM2S + S2MM -> PS S_AXI_HP0_FPD)
set axi_sc_mem [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_sc_mem]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] $axi_sc_mem

connect_bd_net [get_bd_pins clk_wiz_core/clk_out1]       [get_bd_pins fir_core/clk]
connect_bd_net [get_bd_pins rst_core/peripheral_aresetn] [get_bd_pins fir_core/rst_n]

connect_bd_net [get_bd_pins clk_wiz_core/clk_out1]       [get_bd_pins axi_dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins clk_wiz_core/clk_out1]       [get_bd_pins axi_dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins clk_wiz_core/clk_out1]       [get_bd_pins axi_dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins rst_core/peripheral_aresetn] [get_bd_pins axi_dma/axi_resetn]

connect_bd_net [get_bd_pins clk_wiz_core/clk_out1]         [get_bd_pins axi_sc_ctrl/aclk]
connect_bd_net [get_bd_pins rst_core/interconnect_aresetn] [get_bd_pins axi_sc_ctrl/aresetn]
connect_bd_net [get_bd_pins clk_wiz_core/clk_out1]         [get_bd_pins axi_sc_mem/aclk]
connect_bd_net [get_bd_pins rst_core/interconnect_aresetn] [get_bd_pins axi_sc_mem/aresetn]

connect_bd_intf_net [get_bd_intf_pins ps8/M_AXI_HPM0_FPD]  [get_bd_intf_pins axi_sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_ctrl/M00_AXI] [get_bd_intf_pins fir_core/s_axil]
connect_bd_intf_net [get_bd_intf_pins axi_sc_ctrl/M01_AXI] [get_bd_intf_pins axi_dma/S_AXI_LITE]

connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXIS_MM2S] [get_bd_intf_pins fir_core/s_axis]
connect_bd_intf_net [get_bd_intf_pins fir_core/m_axis]     [get_bd_intf_pins axi_dma/S_AXIS_S2MM]

connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_MM2S]  [get_bd_intf_pins axi_sc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_S2MM]  [get_bd_intf_pins axi_sc_mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_mem/M00_AXI]  [get_bd_intf_pins ps8/S_AXI_HP0_FPD]

make_bd_pins_external [get_bd_pins fir_core/ovf_sticky_o]

assign_bd_address
# Ensure fir_core maps at 0xA0000000 for uniform Phase 1 XSDB bring-up checks
set fir_seg [get_bd_addr_segs -quiet ps8/Data/SEG_fir_core_reg0]
if {$fir_seg ne ""} {
  set_property offset 0xA0000000 $fir_seg
}

validate_bd_design
save_bd_design

set bd_file [get_files "${BD_NAME}.bd"]
make_wrapper -files $bd_file -top -import
set_property top "${BD_NAME}_wrapper" [current_fileset]
update_compile_order -fileset sources_1

puts "=== STAGE 2E-2 BLOCK DESIGN GENERATED & VALIDATED ($BUILD_DIR/${DESIGN_NAME}.xpr) ==="
if {![info exists ::CANARY_SOURCED_FROM_BUILD]} {
  exit
}
