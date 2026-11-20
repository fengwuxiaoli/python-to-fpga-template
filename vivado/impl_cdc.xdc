# ==============================================================================
# Implementation-Only Async CDC & Reset Fanout Constraints (Lesson L11)
# Tagged `USED_IN {implementation}` in `vivado/create_bd.tcl` so OOC synthesis
# never emits missing-clock warnings before post-link elaboration.
# ==============================================================================

# Async CDC between PS FCLK (`pl_clk0`) and MMCM core clock (`clk_out1`)
set_clock_groups -asynchronous \
  -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *ps8*pl_clk0*]] \
  -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *clk_wiz_core*clk_out1*]]

# Bound peripheral_aresetn fanout per clock region to avoid global BUFG hold/setup skew
set_property -quiet MAX_FANOUT_MODE CLOCK_REGION [get_nets -quiet *rst_core/U0/peripheral_aresetn[0]]
set_property -quiet FORCE_MAX_FANOUT 256         [get_nets -quiet *rst_core/U0/peripheral_aresetn[0]]
