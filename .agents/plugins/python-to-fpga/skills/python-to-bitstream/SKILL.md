---
name: python-to-bitstream
description: >-
  Guides an end-to-end Python golden-reference to synthesizable SystemVerilog,
  Vivado static lint, XSim co-simulation, OOC synthesis, IPI Block Design,
  timing closure, and FPGA bitstream bring-up workflow. Use whenever designing
  new FPGA/DSP blocks, verifying RTL against Python .mem vectors, fixing Vivado
  build/timing/XSim issues, or generating Zynq bitstreams and JTAG bring-up scripts.
---

# Python-to-Bitstream Workflow Runbook

## Overview
Follow this staged **Path 2 (Python Golden -> Direct SystemVerilog RTL -> Bitstream)** runbook whenever creating or modifying FPGA DSP/hardware modules. Always enforce fast inner loops (**Stage 1, 2B, 2C, 2E-1**) before slow top-level gates (**Stage 2D, 2E-2, 2E-3, 2F**).

## Prerequisites
- **Python 3.10+** (pure stdlib preferred for golden verification; avoid external dependencies where simple math suffices)
- **AMD Vivado / XSDB CLI** (`xvlog`, `xelab`, `xsim`, `vivado`, `xsdb`)
- **Optional MCP Tools:** If `vivado` or `vivado-doc-search` MCP servers are active, use `vivado-doc-search` to check UltraScale+/7-series primitive and IP parameters before Stage 2A/2E authoring. Always ensure batch scripts in `sim/` and `vivado/` work standalone without MCP.

Before writing any RTL (Stage 2A) or Vivado integration Tcl/XDC (Stage 2E), read:
- [references/lessons_learned.md](references/lessons_learned.md) — Failure modes & preventive gates
- [references/vivado_recipes.md](references/vivado_recipes.md) — Parameterized Tcl, IPI wrapper, XDC, and XSDB snippets

---

## Scaffolding a New DSP Block

To avoid missing test harnesses or inconsistent file layout, scaffold every new block with [scripts/scaffold_block.py](scripts/scaffold_block.py):

```powershell
py <skill_dir>/scripts/scaffold_block.py --block <snake_case_name> --repo . [--magic <4CHAR>]
```

---

## Stage-by-Stage Execution Checklist

### Stage 1 — Python Golden Reference & `.mem` Vectors (`~0.5–15 s`)
1. Implement floating-point and **bit-exact fixed-point** functions in `python/<block>_golden.py`.
   - Match integer arithmetic exactly: right-shift rounding `(acc + (1 << (F-1))) >> F` maps 1:1 to SystemVerilog signed `>>>` (both round toward negative infinity on ties, unlike `int(x)` truncation).
2. Add an executable self-test verifying passband/stopband metrics, fixed-vs-float error bound, and overflow/saturation cases.
3. Export 2's-complement `$readmemh` files (`val & ((1 << WIDTH) - 1)`) via `python/generate_<block>_vectors.py` into `test_vectors/`.
4. **EXIT GATE (MANDATORY):** Present the Python results/plots and fixed-point widths to the user and **wait for explicit approval** before creating or editing `.sv` files.

### Stage 2A — Synthesizable SystemVerilog Authoring (`1–10 min`)
1. Add a 32-bit AXI4-Lite slave (`0x000` read-only ASCII `VERSION` ID, `0x004` `CTRL` bypass/enable, `0x008` R/W1C `STATUS`).
2. Keep shift/delay chains **reset-free** (`= '{default: '0}`) so Vivado infers `SRLC16E`/`SRLC32E` instead of exploding FFs/LUTs.
3. Keep data-path multipliers (`MREG`) and accumulators (`PREG`) reset-free so `DSP48E2` internal registers pack cleanly without LUT reset muxes.
4. Put synchronous `rst_n` ONLY on valid/control flip-flops (`v_s1..v_sN`, `core_tvalid`), track valid bits independently of `s_axis_tvalid` so tail samples drain cleanly under stall, and insert a 2-entry `axis_skid` buffer at subsystem/CDC boundaries.

### Stage 2B — Fast RTL Syntax & Static Lint Gate (`~15–60 s`)
1. Add new RTL files **and** the Verilog-2001 IPI wrapper (`vivado/*_bd_wrapper.v`) to `sim/run_lint.*` and `vivado/run_lint.tcl`.
2. Run `sim/run_lint.bat` (Windows) or `./sim/run_lint.sh` (Linux).
3. **EXIT GATE:** `xvlog -sv` exits `0`, `synth_design -lint` exits `0`, zero inferred latches, zero multi-driven nets, zero port width mismatches.

### Stage 2C — Per-Block Unit XSim Co-Simulation (`~10–45 s`)
1. Build a self-checking testbench (`tb/tb_<block>.sv`) reading `test_vectors/*.mem` via `+VEC_DIR=...`.
2. Verify all 4 conditions: AXI4-Lite `VERSION`/reset defaults, golden dataset with random `tvalid` bubbles + `tready` backpressure, runtime coefficient/config rewrite via AXI4-Lite (after flushing `TAPS-1` zeros through reset-free SRLs), and bypass mode.
3. In runner scripts, always clean prior `xsim.dir`, assert `if not exist xsim.dir\<snap>\xsimk.exe`, print a single `ALL TESTS PASSED (0 ERRORS)` marker, call `$fatal(1, ...)` on error, and delete `xvlog.*/xelab.*/xsim.*`/`xsim.dir` after completion.
4. **EXIT GATE:** `0` bit mismatches across all scenarios and exit code `0`.

### Stage 2D — Top-Level Integration XSim (`~1–15 min`)
1. Wire subsystems at top level; run a **short smoke simulation** (1–2 frames) first for wiring checks, then a full multi-rate soak test for sign-off.
2. **EXIT GATE:** `100%` of Stage 2B/2C already passed + `0` end-to-end mismatches.

### Stage 2E — Tiered OOC Budget, IPI Block Design & Physical Closure
1. **2E-1 OOC Block Budget (`vivado/run_ooc_synth.tcl`):** Run `-mode out_of_context` on individual DSP/BRAM blocks first to catch `WNS < 0` or missing DSP/SRL inference in `< 60 s`.
2. **2E-2 IPI Block Design & Top Synth (`vivado/create_bd.tcl`, `build_bitstream.tcl -tclargs synth`):**
   - Isolate project build directory in `%TEMP%` or `FPGA_BUILD_DIR` (never inside OneDrive or non-ASCII paths).
   - Expose SV tops to `create_bd_cell -type module` through a thin SV flattener (if 2D/unpacked ports exist) + pure **Verilog-2001** `*_bd_wrapper.v` with `X_INTERFACE_INFO` / `X_INTERFACE_PARAMETER`.
   - Query `ps8/pl_clk0` frequency dynamically via `get_property CONFIG.FREQ_HZ`.
   - Separate async `set_clock_groups`, `CLOCK_DELAY_GROUP`, and `MAX_FANOUT_MODE CLOCK_REGION` into `impl_cdc.xdc` with `set_property USED_IN {implementation}`.
   - Write `checkpoints/post_synth.dcp`, `reports/post_synth_util.rpt`, `reports/post_synth_timing.rpt`.
3. **2E-3 Implementation / P&R (`build_bitstream.tcl -tclargs impl`):**
   - Write `checkpoints/post_route.dcp`.
   - **EXIT GATE:** `WNS >= 0 ns`, `TNS = 0 ns`, `WHS >= 0 ns`, `THS = 0 ns`, `WPWS >= 0 ns`, 100% routed nets, `0` DRC errors.

### Stage 2F — Bitstream, Fixed XSA & Hardware Bring-Up
1. Run `build_bitstream.tcl -tclargs bitstream` to emit `${DESIGN_NAME}.bit` and `write_hw_platform -fixed -include_bit -force`.
2. Follow **Phase 1** (standalone JTAG `psu_init` -> `fpga` -> `psu_post_config` -> `psu_ps_pl_isolation_removal` -> `psu_ps_pl_reset_config` -> read `VERSION` at `0xA0000000`) via `bringup/jtag_bringup.tcl` before connecting external PHY/RF links in **Phase 2**.
