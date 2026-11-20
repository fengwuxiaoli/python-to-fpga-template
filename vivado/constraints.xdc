# ==============================================================================
# Stage 2E-2 / 2E-3 Physical & Timing Constraints Template
# Default Board Reference: AMD ZCU102 (xczu9eg-ffvb1156-2-e)
# Replace or extend pin locations below when adding external I/O or targeting
# another board (`FPGA_PART` / `FPGA_BOARD_PART` in `vivado/board_config.tcl`).
# ==============================================================================

# Asynchronous LED / GPIO status output (crosses from core clock to board I/O)
set_false_path -to [get_ports -quiet ovf_sticky_o*]

# Example ZCU102 User LED0 constraint (uncomment when targeting physical ZCU102 hardware):
# set_property PACKAGE_PIN AG14     [get_ports ovf_sticky_o_0]
# set_property IOSTANDARD  LVCMOS33 [get_ports ovf_sticky_o_0]

# NOTE: Inter-domain async `set_clock_groups` and high-fanout reset directives
# belong in `vivado/impl_cdc.xdc` (`USED_IN {implementation}`) so OOC IP synthesis
# runs cleanly without black-box clock warnings (Lesson L11).
