# Signal Processing (SP) & FPGA Hardware Design Rules

Projects using this plugin follow **Path 2 (SPEC.md Requirements -> Python Golden Reference -> Direct Synthesizable SystemVerilog RTL -> FPGA Bitstream)** with strict fast-loop vs. slow-gate discipline to prevent costly EDA delays and silent fixed-point mismatches.

## 0. Stage 0 — Requirements Specification First (Mandatory Agreement Gate)
Before designing or modifying any DSP, RF, packet-processing, or FPGA hardware block:

1. **Stage 0 — Collaborative Requirements Specification (`SPEC.md`):**
   - Start from `skills/python-to-bitstream/references/spec_template.md` and collaboratively write **`SPEC.md`** with the user.
   - Explicitly resolve and document: scope and non-goals; target part, clock frequency, reset policy, throughput/latency, and resource budgets; mathematical algorithm, operating modes, and framing/edge cases; fixed-point Q-formats, rounding, saturation, and numerical targets; hardware interfaces and AXI4-Lite register map (including `0x00 VERSION`); Stage 1–2F verification/acceptance criteria; and the Open Questions & Assumptions log.
   - **STOP and do NOT advance to Stage 1** (do not write `python/*_golden.py`, generate `.mem` vectors, run `scaffold_block.py`, or write any HDL) until `0` open questions remain and the user explicitly agrees with **every item** in `SPEC.md` (`Status: APPROVED`).
   - **Change Control:** If Stage 1 exploration or Stage 2 implementation reveals a required change to agreed requirements, update `SPEC.md` and re-confirm agreement with the user before changing downstream code.

## 1. Stage 1 — Python Golden Reference & Vectors (Mandatory Approval Gate)
Only after **Stage 0 (`SPEC.md`) is fully agreed and approved**:

1. **Stage 1 — Python Golden Reference & Vectors (`~0.5–15 s`):**
   - Implement both a floating-point reference and a **bit-exact fixed-point Python Golden Reference** (`<block>_golden.py`) matching `SPEC.md`.
   - Verify quantitative algorithm behavior (frequency response, EVM/ACLR, overflow bounds, or packet state) against the acceptance criteria agreed in `SPEC.md` and export `$readmemh` `.mem` stimulus/golden vectors (`generate_<block>_vectors.py`).
   - **STOP and wait for explicit user approval** of the fixed-point architecture, bit widths, and Python results before writing any HDL (SystemVerilog/VHDL).

## 2. Stage 2 — Sub-Staged RTL-to-Bitstream Flow (Fast Loop vs. Slow Gates)
Only after the user approves Stage 1, execute Stage 2 in order. **Never invoke a slow gate (`2D`, `2E-2`, `2E-3`) to debug arithmetic, FSM, or syntax bugs that belong in fast inner loops (`2B`, `2C`).**

1. **Stage 2A — Microarchitecture Planning & Synthesizable SV Authoring (`1–10 min`, 0 EDA wait):**
   - Translate the approved fixed-point Python model into pipelined, synthesizable SystemVerilog (`rtl/*.sv`) with explicit AXI4-Stream/AXI4-Lite handshakes and a read-only `VERSION` ID register (`0x000`).
   - Consult AMD documentation (`vivado-doc-search` MCP if installed) and `skills/python-to-bitstream/references/lessons_learned.md` for `SRLC16E`, DSP48E2, and BRAM inference rules before coding.

2. **Stage 2B — Fast RTL Syntax & Static Lint Gate (`< 3 s` `xvlog`, `~15–60 s` `synth_design -lint`):**
   - Run `xvlog -sv` and Vivado `synth_design -lint` on all modified SV files **and** any Verilog-2001 IPI wrapper before launching simulation or synthesis.
   - Fix all syntax errors, latch inferences, multi-driven nets, and port-width mismatches here.

3. **Stage 2C — Per-Block Unit XSim Co-Simulation (`~10–45 s`/block):**
   - Verify each block in Vivado XSim against Stage 1 `.mem` golden vectors under randomized `tvalid` bubbles and `tready` backpressure with **`0` bit mismatches** (or documented fixed-point LSB bound).
   - Assert both non-zero exit codes AND that the elaborated snapshot executable (`xsimk.exe` on Windows) exists before declaring XSim green.
   - **Fast Inner Loop:** Perform all arithmetic, rounding, pipeline-drain, and FSM debugging in 2C.

4. **Stage 2D — RTL Top Integration & Full-Chain XSim Gate (`~1–2 min` smoke / `~10–17 min` soak):**
   - Run **only after 100% of 2B and 2C pass**.
   - Use short smoke runs (`1–2` frames/symbols) for inter-block wiring checks; reserve full-length multi-rate soak runs for milestone sign-off.

5. **Stage 2E — Tiered Synthesis, Board IPI/XDC Integration & Implementation:**
   - **2E-1 Block OOC Budget (`~30 s–5 min`/block):** Run `-mode out_of_context` synthesis on new or DSP/BRAM-heavy blocks to check `WNS >= 0` and resource inference early.
   - **2E-2 Board IPI/XDC + Top Synthesis:** Freeze RTL after 2D before building the Block Design (`zynq_ultra_ps_e`, dynamic `FREQ_HZ` clocking, thin Verilog-2001 `*_bd_wrapper.v`), keeping async `set_clock_groups` in a separate `impl_cdc.xdc` tagged `USED_IN {implementation}`, and caching Vivado IP OOC runs.
   - **2E-3 Physical Implementation / P&R:** Run checkpointed `opt_design` -> `place_design` -> `route_design` (`post_synth.dcp` / `post_route.dcp`) until `WNS >= 0 ns`, `TNS = 0 ns`, `WHS >= 0 ns`, `THS = 0 ns`, `WPWS >= 0 ns`, and `0` DRC/routing errors.

6. **Stage 2F — Bitstream, Fixed XSA & Hardware Validation:**
   - Generate `.bit` and `write_hw_platform -fixed -include_bit -force` `.xsa` only after clean P&R (`2E-3`).
   - Run Phase 1 standalone board verification (JTAG `psu_init` -> `fpga` -> `psu_post_config` -> `psu_ps_pl_isolation_removal` -> AXI4-Lite `VERSION` readback) before Phase 2 external PHY/RF bench tests.
   - Deliver `sw/` register headers (`<block>_regs.h` / `<block>_regs.py`) and `INTEGRATION.md` (starting from `skills/python-to-bitstream/references/integration_template.md`) for downstream SW and RTL integrators while keeping `.bit`, `.xsa`, `.dcp`, `.rpt`, and `.zip` archives out of Git.

## 3. Repository Hygiene & Path Isolation Rules
- **Isolate Vivado Builds Out-of-Tree:** Never create `.xpr`, `.runs`, or `.cache` directories inside OneDrive-synced folders, paths with spaces, or non-ASCII paths. Default Vivado build artifacts to `%TEMP%` / `/tmp` (overridable via `FPGA_BUILD_DIR`).
- **Clean Repo Discipline:** Never commit Vivado/XSim/Python artifacts (`*.log`, `*.jou`, `*.pb`, `*.wdb`, `*.dcp`, `*.bit`, `*.xsa`, `*.Xil`, `xsim.dir/`, `__pycache__/`, `*.png`, `*.pdf`). Clean temporary `xvlog`/`xelab`/`xsim` files at the end of simulation scripts.
