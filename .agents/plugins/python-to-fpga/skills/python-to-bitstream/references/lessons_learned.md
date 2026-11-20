# Lessons Learned Catalog (Python -> RTL -> Bitstream)

Every entry below records a real failure mode encountered during an end-to-end 245.761 MHz Zynq UltraScale+ (`xczu9eg`) FPGA design and distilled into a concrete gate rule.

---

## L1 — Signed `.mem` Export & Arithmetic Shift Parity
- **Stage & Trigger:** **Stage 1** when exporting negative Q-format values to hex `.mem` files or matching fixed-point Python right-shifts to SystemVerilog `>>>`.
- **Failure Mode & Cost:** Writing `f"{val:04X}"` for negative Python ints writes `-00D6`, causing `$readmemh` parse errors or silent zeroing in XSim. Meanwhile, using Python `int(acc / (1 << F))` truncates toward zero while SV signed `>>>` shifts toward `-infinity`, causing persistent `1 LSB` mismatches on negative samples that derail Stage 2C sign-off.
- **Preventive Pattern:**
  - Always mask signed integers with the exact bit width on export: `f"{val & ((1 << WIDTH) - 1):0{WIDTH // 4}X}\n"`.
  - Match fixed-point rounding using integer arithmetic shift in both languages: Python `(acc + (1 << (F - 1))) >> F` paired with SystemVerilog `(acc + (1 <<< (F - 1))) >>> F` on an explicitly `signed` extended accumulator.
- **Verification Check:** Exercise high-amplitude alternating positive/negative inputs in Python and confirm `0` bit mismatches in XSim Stage 2C.

---

## L2 — Reset-Free Shift Chains for `SRLC16E` Inference
- **Stage & Trigger:** **Stage 2A** when coding multi-tap FIR delay lines or pipeline history shift registers (`d[0:N-1]`).
- **Failure Mode & Cost:** Adding `if (!rst_n)` inside the shift-register `always_ff` forces Vivado to synthesize discrete flip-flops and reset muxes instead of packing 16–32 stages per LUT into `SRLC16E`/`SRLC32E`, bloating LUT/FF counts and driving routing congestion.
- **Preventive Pattern:**
  - Leave data shift chains completely **reset-free** (`always_ff @(posedge clk) if (shift_en) ...`).
  - Initialize array storage for power-on / XSim determinism with declaration initialization: `logic signed [15:0] d [0:N-1] = '{default: 16'sd0};`.
  - Only apply `rst_n` to valid/control flip-flops (`v_s1..v_sK`, `out_valid`).
  - Flush `TAPS - 1` zero samples between dynamic test scenarios in Stage 2C testbenches instead of asserting `rst_n` to clear data history.
- **Verification Check:** Inspect Stage 2E-1 OOC utilization (`ooc_util.rpt`) and confirm `SRL` primitives are inferred (`SRL16E` / `SRLC32E` > 0) for delay chains >= 4 taps.

---

## L3 — DSP48E2 & BRAM Pipeline Packing
- **Stage & Trigger:** **Stage 2A / 2E-3** when targeting `>= 200 MHz` on UltraScale+ (`DSP48E2`, `RAMB36E2`).
- **Failure Mode & Cost:** Putting synchronous resets on operand/product registers or connecting combinatorial logic directly out of block RAM without `DOB_REG` forces Vivado to pull registers outside `DSP48E2` (`AREG`/`MREG`/`PREG`) and `BRAM` primitives into fabric LUTs, costing > 1.5 ns per stage and failing timing (`WNS < 0`).
- **Preventive Pattern:**
  - Register operands cleanly before the multiply (`p_s1`), register products in an unreset `always_ff` (`prod_s2`), and use a balanced registered adder tree into the final accumulator.
  - Give all BRAM reads a 2-cycle registered read pipeline so Vivado packs `OREG`/`DOB_REG` inside the block RAM, and merge duplicate read/write ports into unified TDP ports.
- **Verification Check:** Confirm Stage 2E-1 OOC reports expected `DSP48E2` / `RAMB*` counts and `WNS >= 0 ns` at `TARGET_CLK_MHZ`.

---

## L4 — AXI4-Stream Drain Under Bubbles & Combinational `tready` Loops
- **Stage & Trigger:** **Stage 2A / 2C / 2E-2** when pipelining DSP cores on `s_axis_*` / `m_axis_*`.
- **Failure Mode & Cost:**
  1. Gating internal pipeline advancement on `s_axis_tvalid` freezes the final `K` tail samples inside the pipe at the end of a burst.
  2. Wiring `assign s_axis_tready = m_axis_tready && ...` across subsystem or CDC boundaries creates long multi-block combinational `tready` paths that fail setup timing in Stage 2E-3.
- **Preventive Pattern:**
  - Advance the DSP pipeline on `pipe_en = !core_tvalid || core_tready`, propagate per-stage valid bits (`v_s1`, `v_s2`, ...), and inject zeros only into the delay-line write enable (`s_axis_tvalid && pipe_en`) — NOT `pipe_en` itself!
  - Insert a registered 2-entry `axis_skid` buffer at module/CDC boundaries to break both forward `tvalid/tdata` and backward `tready` timing paths.
- **Verification Check:** Stage 2C testbench MUST drive pseudo-random `s_axis_tvalid` gaps **and** pseudo-random `m_axis_tready` backpressure stalls simultaneously with `0` dropped or duplicated beats.

---

## L5 — LUT & Congestion Reduction via TDM Folding
- **Stage & Trigger:** **Stage 2A / 2E-3** when multi-antenna or multi-channel symmetric FIR filters consume excessive fabric LUTs (> 50%) and cause router congestion (`Route 35-54` or degraded WNS).
- **Failure Mode & Cost:** Unrolling an entire multi-antenna filter bank per channel duplicates symmetric pre-adders and adder trees, consuming tens of thousands of extra LUTs even when clock rate exceeds sample rate (`II >= 2` or `4`).
- **Preventive Pattern:**
  - Time-division multiplex (`TDM`, `II = N`) parallel low-rate streams onto shared `DSP48E2` chains backed by BRAM FWFT FIFOs, registered arbiter backpressure, and fanout-bounded local reset/config registers (cut Filter Branch LUTs by ~55% in the reference 5G O-RAN vDU).
- **Verification Check:** Compare Stage 2E-1 LUT/DSP utilization against device budget before integrating `N` copies into Block Design.

---

## L6 — Hardware Liveness `VERSION` Register at Offset `0x000`
- **Stage & Trigger:** **Stage 2A / 2F** during initial FPGA silicon bring-up over JTAG/XSDB/PYNQ.
- **Failure Mode & Cost:** Without a fixed non-zero read-only constant register, reading `0x00000000` on an uninitialized register looks indistinguishable from a stuck AXI interconnect, missing PL clock (`clk_wiz` unlocked), or locked PS-PL isolation bridge.
- **Preventive Pattern:**
  - Map a 4-byte ASCII constant `VERSION` register at byte offset `0x000` of every AXI4-Lite peripheral (e.g., `32'h46495231` = `"FIR1"`).
  - Reserve `0x004` for `CTRL` (soft bypass/enable) and `0x008` for sticky R/W1C `STATUS` (overflow/error latches).
- **Verification Check:** Verify `VERSION` readback in Stage 2C `tb_*.sv` AND as the very first hardware check in Stage 2F `jtag_bringup.tcl`.

---

## L7 — Stage 2B Static Lint Gate Including the IPI Wrapper
- **Stage & Trigger:** **Stage 2B** before launching XSim or 30-minute Vivado BD synthesis.
- **Failure Mode & Cost:** Linting only `rtl/*.sv` misses port width mismatches, missing net declarations, or typoed connections in the Verilog-2001 Block Design wrapper (`*_bd_wrapper.v`), blowing up late inside Stage 2E-2 synthesis.
- **Preventive Pattern:**
  - Always include both `rtl/*.sv` **and** `vivado/*_bd_wrapper.v` in `sim/run_lint.*` and `vivado/run_lint.tcl` (`synth_design -lint -top *_bd_wrapper`).
  - Fail fast in `< 60 s` on any latch inference, multi-driven net, or width warning.
- **Verification Check:** `sim/run_lint.bat` / `sim/run_lint.sh` exits `0` before every Stage 2C / 2E run.

---

## L8 — Windows XSim `xelab` Silent/Stale Snapshot Trap
- **Stage & Trigger:** **Stage 2C** when running XSim batch scripts (`xvlog` -> `xelab` -> `xsim`) on Windows.
- **Failure Mode & Cost:** In `.bat` scripts, `xelab` can fail or abort after writing partial snapshot files without always tripping naive downstream assumptions, causing `xsim` to re-run a **stale prior `xsimk.exe` snapshot** and falsely report yesterday's `PASS`.
- **Preventive Pattern:**
  - Delete `xsim.dir/<snap>`, `xvlog.*`, `xelab.*`, and `xsim.*` **before** running `xvlog`.
  - Check `%ERRORLEVEL%` after every tool invocation **and** explicitly verify `if not exist xsim.dir\<snap>\xsimk.exe exit /b 1` before calling `xsim`.
  - On Windows `xsim.bat`, `cmd.exe` treats unquoted `=` as an argument delimiter, so always quote plusargs (`-testplusarg "KEY=VAL"`).
  - Call `$fatal(1, ...)` on any testbench error so `xsim` returns a non-zero status.
- **Verification Check:** Temporarily inject a 1-bit mismatch in stimulus/TB once and confirm `run_sim_*.bat` exits with non-zero status.

---

## L9 — Windows `MAX_PATH`, Spaces, Non-ASCII & OneDrive Lock Trap
- **Stage & Trigger:** **Stage 2B / 2E** when the repository lives under OneDrive-synced folders, paths containing spaces (e.g., `Python Scripts`), or non-ASCII folders, or when passing unbraced file paths to Vivado Tcl (`read_verilog $file`).
- **Failure Mode & Cost:**
  1. Vivado GUI/Tcl synthesis, IP generation, and `opt_design` lock files against OneDrive sync threads or fail with cryptic C++/Tcl path errors exceeding Windows 260-char limits (`Vivado` `.runs/impl_1/...` trees run 100+ chars deep).
  2. Passing a bare scalar variable (`read_verilog $BD_WRAPPER_FILE`) instead of a single-element list (`read_verilog [list $BD_WRAPPER_FILE]`) splits the path on spaces (`File '.../Python' does not exist`).
- **Preventive Pattern:**
  - Always place `$BUILD_DIR` out-of-tree in `%TEMP%/<project>` (or `/tmp/<project>`), overridable via `FPGA_BUILD_DIR`, via a centralized `vivado/board_config.tcl`.
  - Always pass file arguments to `read_verilog` / `add_files` as proper Tcl lists (`[list $file]` / `lappend`), never bare variables or `concat` on raw strings.
  - In XSim batch runners under synced/non-ASCII workspace roots, `pushd` into `sim/` and pass **relative paths** (`..\rtl\*.sv`, `../test_vectors`) rather than expanding full non-ASCII absolute paths on command lines.
- **Verification Check:** Inspect `board_config.tcl`, run `sim/run_lint.*` from a path containing spaces, and confirm zero `.xpr` or `.runs` folders ever appear inside the Git working tree.

---

## L10 — Vivado IPI Rejects SystemVerilog Packages & 2D/Unpacked Ports
- **Stage & Trigger:** **Stage 2E-2** when calling `create_bd_cell -type module -reference <rtl_top>` in Vivado IP Integrator.
- **Failure Mode & Cost:** Vivado Block Design module references cannot parse SystemVerilog packages in port lists, `logic` unpacked arrays (`m_axis_rf[0:3]`), or 2D packed vectors directly on module-reference boundaries (`BD 41-xxx` errors).
- **Preventive Pattern:**
  - If your SV top uses unpacked arrays or SV structs/packages on ports, add a thin SV flattener bridge (`*_sv_bridge.sv`) converting all I/O to 1D vectors.
  - Wrap the top module with a pure **Verilog-2001** `*_bd_wrapper.v` carrying explicit `(* X_INTERFACE_INFO *)` and `(* X_INTERFACE_PARAMETER *)` attributes for clocks, resets, AXI4-Lite, and AXI4-Stream interfaces.
- **Verification Check:** `validate_bd_design` completes with `0` critical warnings/errors and auto-associates clock/reset domains cleanly.

---

## L11 — Dynamic PS `pl_clk0` Query & Implementation-Only CDC XDC
- **Stage & Trigger:** **Stage 2E-2 / 2E-3** when wiring `clk_wiz` to `zynq_ultra_ps_e/pl_clk0` and constraining async clock crossings + global resets.
- **Failure Mode & Cost:**
  1. Hardcoding `CONFIG.PRIM_IN_FREQ 100.0` mismatches actual ZCU102 `pl_clk0` (`99.99 MHz`), triggering Clock Wizard DRC errors.
  2. Placing `set_clock_groups -asynchronous` referencing OOC IP internal clock pins inside default constraints triggers `CRITICAL WARNING` during OOC or pre-link synthesis because those OOC pins are black boxes until link.
  3. Letting a global PL reset fan out across 10,000+ flip-flops over a single `BUFG` creates catastrophic hold/setup violations during `route_design`.
- **Preventive Pattern:**
  - Read `set pl0_mhz [expr {[get_property CONFIG.FREQ_HZ [get_bd_pins ps8/pl_clk0]] / 1.0e6}]` dynamically in Tcl.
  - Keep inter-domain `set_clock_groups -asynchronous`, `CLOCK_DELAY_GROUP`, and reset fanout bounds (`MAX_FANOUT_MODE CLOCK_REGION`, `FORCE_MAX_FANOUT 256` on `rst_*/peripheral_aresetn`) inside a separate `impl_cdc.xdc` tagged `set_property USED_IN {implementation} [get_files *impl_cdc.xdc]`.
- **Verification Check:** Inspect synthesis logs (`0` missing-clock warnings) and `report_clock_interaction` / `report_bus_skew` after `route_design`.

---

## L12 — OOC IP Caching & `.dcp` Checkpoint Gating
- **Stage & Trigger:** **Stage 2E-2 / 2E-3** during iterative RTL/constraint timing closure on multi-IP Block Designs.
- **Failure Mode & Cost:** Calling `reset_run` or rebuilding the entire project from scratch forces Vivado to re-synthesize heavy PS, Ethernet, JESD204C, and DMA IPs (~20–40 min) on every single RTL or XDC tweak.
- **Preventive Pattern:**
  - Keep the `.xpr` project persistent in `$BUILD_DIR` with OOC IP runs cached; only re-run `synth_1` when RTL changes, and re-run `impl_1` from `post_synth.dcp` when iterating XDC constraints.
  - Structure `build_bitstream.tcl` with explicit `-tclargs synth | impl | bitstream | all` stages saving `post_synth.dcp` and `post_route.dcp` plus utilization/timing reports at each gate.
- **Verification Check:** Refuse bitstream generation unless `post_route_timing.rpt` meets `WNS >= 0`, `TNS = 0`, `WHS >= 0`, `THS = 0`, `WPWS >= 0`, and `0` DRC errors.

---

## L13 — Fixed XSA Export, XSDB PS-PL Isolation Removal & Phase 1/2 Bring-Up
- **Stage & Trigger:** **Stage 2F** during JTAG programming and board-level AXI verification.
- **Failure Mode & Cost:**
  1. Running `write_hw_platform` without `-fixed -include_bit` creates an XSA unusable for standalone PYNQ/Vitis/XSDB flows.
  2. In XSDB JTAG bring-up on Zynq UltraScale+ MPSoC, running only `fpga -f system.bit` programs the PL while the PS remains uninitialized and the **PS-PL level-shifter isolation bridges remain locked**, causing AXI reads from Cortex-A53/JTAG to hang the bus (`DAP ACK` timeout).
  3. Debugging Ethernet/RF/JESD links simultaneously with PL logic hides which domain is broken.
- **Preventive Pattern:**
  - Always export `write_hw_platform -fixed -include_bit -force -file <name>.xsa`.
  - Extract `<name>.bit` + `psu_init.tcl` from `.xsa` in `jtag_bringup.tcl` and run the mandatory sequence: `rst -system` -> `psu_init` -> `fpga -no-revision-check` -> `psu_post_config` -> `psu_ps_pl_isolation_removal` -> `psu_ps_pl_reset_config`.
  - Split bench bring-up into **Phase 1** (standalone board: JTAG/XSDB/DMA loopback + `VERSION` check) before **Phase 2** (external cables/RF/PHY links).
- **Verification Check:** `VERSION` readback over XSDB returns the exact `0x46495231` ASCII magic ID before touching external bench hardware.
