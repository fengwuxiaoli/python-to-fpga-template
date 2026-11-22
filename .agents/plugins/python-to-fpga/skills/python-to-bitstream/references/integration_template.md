# Hardware & Software Integration Guide (`INTEGRATION.md`)

> **Stage 2F Integration Handoff Template:**  
> Copy this template to `INTEGRATION.md` at the repository root and complete every section once **Stage 2E-3** (timing closure) and **Stage 2F** (bitstream / `.xsa` export & Phase 1 bring-up) pass. Keep binary outputs (`.bit`, `.xsa`, `.dcp`, `.rpt`, `.zip`) out of Git—store them out-of-tree (`$FPGA_BUILD_DIR` / `%TEMP%`) or attach them to versioned releases outside Git.

---

## Release & Build Traceability

| Field | Value |
| :--- | :--- |
| **Block / Design Name** | `<design_name>` |
| **Release Version / Git Tag** | `<e.g., v1.0.0 / git commit SHA>` |
| **Expected `VERSION` Register (`0x00`)** | `<0xXXXXXXXX ("XXXX")>` |
| **Target Part / Board** | `<e.g., xczu9eg-ffvb1156-2-e / xilinx.com:zcu102:part0:3.4>` |
| **Primary PL Clock** | `<e.g., 245.761 MHz (4.069 ns period)>` |
| **Vivado Version** | `<e.g., 2026.1>` |
| **Timing & Verification Summary** | `<e.g., Post-route WNS >= 0, TNS = 0, WHS >= 0, THS = 0, WPWS >= 0, 0 DRC; Stage 2C/2D 0 mismatches>` |

---

## 1. Deliverables & 3-Tier Storage Policy

| Storage Tier | Stored Artifacts | Policy / Purpose |
| :--- | :--- | :--- |
| **1. Git Repository (Source of Truth)** | `SPEC.md`, `INTEGRATION.md`, `rtl/*.sv`, `python/*_golden.py`, `tb/tb_*.sv`, `test_vectors/*.mem`, `sim/run_*`, `vivado/*.tcl\|*.v\|*.xdc`, `bringup/*`, `sw/<block>_regs.h`, `sw/<block>_regs.py` | Small, diffable, reproducible source of truth. **Never commit** `.bit`, `.xsa`, `.hwh`, `.ltx`, `.dcp`, `.rpt`, or `.zip` release archives. |
| **2. Out-of-Tree Build Dir (`$FPGA_BUILD_DIR` / `%TEMP%`)** | `<design>.xpr`, `.runs/`, `.cache/`, `checkpoints/post_*.dcp`, `reports/*.rpt`, `<design>.bit`, `<design>.xsa` | Ephemeral local Vivado build outputs configured via `vivado/board_config.tcl`; prevents OneDrive locks and Windows `MAX_PATH` failures. |
| **3. External Release Storage (GitHub Releases / Artifactory / Shared Drive)** | Immutable versioned bundle attached outside Git containing `.bit`, `.xsa` (`-fixed -include_bit`), optional `.hwh`/`.ltx`, timing/util/DRC reports, `sw/` headers, `SPEC.md`, and `INTEGRATION.md` | Tagged against the exact Git commit/release so downstream teams download a verified silicon snapshot. |

---

## 2. Track A — SoC / Embedded Software Integration (Vitis, PetaLinux, PYNQ, Bare-Metal, XSDB)

### 2.1 Required Handoff Files
- **Hardware Binary / Platform:** `<design>.xsa` (built with `write_hw_platform -fixed -include_bit` for Vitis, PetaLinux, or XSDB) and/or `<design>.bit` + `<design>.hwh` (for PYNQ / Linux overlay loading).
- **Register & Bring-Up Helpers:** `sw/<block>_regs.h` (C/C++ Vitis / bare-metal / Linux UIO), `sw/<block>_regs.py` (Python / PYNQ MMIO), and `bringup/jtag_bringup.tcl`.
- **Golden Test Vectors:** `test_vectors/<block>_stim.mem` and `test_vectors/<block>_exp*.mem` for DMA loopback verification.

### 2.2 Programming & PS-PL Release Sequence
1. On Zynq UltraScale+ MPSoC over JTAG (`SW6 = 0000` on ZCU102), **never** run `fpga -f` alone—the PS-PL level shifters remain locked until PS initialization and isolation removal run:
   ```tcl
   rst -system -> source psu_init.tcl -> psu_init -> fpga -no-revision-check -f <design>.bit -> psu_post_config -> psu_ps_pl_isolation_removal -> psu_ps_pl_reset_config
   ```
   Use `bringup/jtag_bringup.tcl` directly (`xsdb bringup/jtag_bringup.tcl <path_to_xsa> <base_addr>`).
2. On booted Linux / PYNQ / FSBL platforms where PS initialization already completed, load the bitstream/overlay and verify `clk_wiz` lock before accessing PL AXI addresses.

### 2.3 Base Address & AXI4-Lite Register Quick-Reference
- **Default Base Address:** `<0xA0000000>` (`<256 B>` address window, `<8-bit>` byte offset).
- **Access Width & `WSTRB` Rule:** Issue full 32-bit aligned reads/writes (`wstrb = 0xF`). `<Document any partial wstrb requirements, e.g., COEFF writes require wstrb[1:0] == 2'b11>`.

| Offset | Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `VERSION` | `RO` | `<0xXXXXXXXX>` | Constant 4-byte ASCII magic ID (`"<XXXX>"`) |
| `0x04` | `CTRL` | `RW` | `0x00000000` | `[0]`: `bypass_en` (`1` = bypass, `0` = normal) |
| `0x08` | `STATUS` | `R/W1C` | `0x00000000` | `[0]`: `ovf_sticky` (write `1` to clear) |
| `0x10..` | `<CUSTOM_REGS>` | `<RW/RO>` | `<Reset>` | `<Register description>` |

### 2.4 Mandatory First Liveness Check & Operational Sequences
1. **Liveness Check (Mandatory First Step):** Read offset `0x00` (`VERSION`) and confirm it equals `<0xXXXXXXXX>`. If it reads `0x00000000` or hangs (`DAP ACK` timeout), stop and check PS-PL isolation removal, PL clock lock, and address map.
2. **Data Streaming & `TLAST`:** `<Specify sample format, endianness, DMA transfer width, and TLAST packet-boundary expectations>`.
3. **Runtime Reconfiguration & Zero-Flush:** `<Specify whether changing coefficients/parameters requires flushing N zero samples through reset-free delay chains>`.
4. **Sticky `STATUS` Handling:** Poll `STATUS[0]` (`ovf_sticky`) after bursts; clear by writing `0x00000001` to `STATUS` (`R/W1C`).
5. **End-to-End DMA Loopback Check:** Stream `test_vectors/<block>_stim.mem` through DMA -> IP -> DMA and confirm bit-exact equality against `test_vectors/<block>_exp*.mem`.

---

## 3. Track B — FPGA RTL / Subsystem Integration (Top-Level RTL or Vivado IPI BD)

### 3.1 Required Source Files
- **Synthesizable RTL:** `rtl/*.sv` (include `rtl/axis_skid.sv` and core/reg submodules).
- **Vivado IPI Boundary:** `vivado/<block>_bd_wrapper.v` (pure Verilog-2001 wrapper with `X_INTERFACE_INFO` / `X_INTERFACE_PARAMETER` attributes for `create_bd_cell -type module`).
- **Constraints Reference:** `vivado/constraints.xdc` (physical/IO/false-path) and `vivado/impl_cdc.xdc` (tagged `USED_IN {implementation}`).

### 3.2 Clock, Reset & CDC Contract
- **Clocking:** Single synchronous PL clock `clk` targeting `<245.761 MHz>` (`<4.069 ns>` period).
- **Reset Warning (`rst_n`):** `rst_n` is **synchronous active-low** and resets **only** AXI4-Lite registers, pipeline valid/control flip-flops, and `axis_skid`. Shift/delay chains and DSP datapath registers are intentionally **reset-free** (`SRL`/`DSP48E2` packing)—asserting `rst_n` does **not** zero out sample delay history; flush `<N>` zero samples if a clean boundary is required between modes.
- **CDC Constraints:** Keep inter-clock `set_clock_groups -asynchronous` and high-fanout reset `MAX_FANOUT_MODE CLOCK_REGION` / `FORCE_MAX_FANOUT` directives in a `USED_IN {implementation}` XDC (`vivado/impl_cdc.xdc`), never in OOC synthesis constraints.

### 3.3 AXI4-Stream Throughput, Latency & Framing Contract
- **Throughput (`II`):** `<II = 1 sample/clock cycle>` when `m_axis_tready = 1`.
- **Pipeline Latency:** `<L>` clock cycles from accepted `s_axis` beat to valid `m_axis` beat under `m_axis_tready = 1`.
- **Backpressure & `TLAST`:** Output is buffered via 2-entry registered `axis_skid`, breaking combinational `tready` loops across subsystem boundaries. `s_axis_tlast` propagates 1:1 with each sample.

### 3.4 Expected Synthesis Resource & Primitive Signature
Check post-synthesis / post-route utilization in the parent design to confirm Vivado did not degrade primitive packing:

| Resource / Metric | Expected Footprint | Verification Note |
| :--- | :---: | :--- |
| **CLB LUTs (Total / SRLs)** | `<e.g., ~178 LUTs (incl. 16 SRL16E)>` | Confirm `SRL` primitives `> 0` (reset-free shift chain intact) |
| **Flip-Flops (FFs)** | `<e.g., ~447 FFs>` | Includes AXI4-Lite, pipeline control, and `axis_skid` |
| **DSP48E2 / BRAM** | `<e.g., 10 DSP48E2, 0 BRAM>` | Confirm `MREG`/`PREG` packed inside DSPs |
| **Latches / DRC** | `0 latches`, `0 DRC errors` | Must pass `synth_design -lint` cleanly |

### 3.5 Parent-Design Verification Checklist
- [ ] Run Stage 2B lint (`xvlog -sv` + `synth_design -lint`) with the parent wrapper wired.
- [ ] Run a Stage 2D smoke simulation driving parent traffic through the block with `tvalid` bubbles and `tready` stalls; verify `0` mismatches and clean `tlast` framing.
- [ ] Confirm `report_utilization` matches Section 3.4 (`SRL`/`DSP48E2` inference intact) and `report_timing_summary` meets `WNS >= 0 ns`, `TNS = 0 ns`, `WHS >= 0 ns`, `THS = 0 ns`, `WPWS >= 0 ns`.

---

## 4. Common Integration Pitfalls & Troubleshooting

| Symptom | Root Cause | Resolution |
| :--- | :--- | :--- |
| AXI read of `0x00 VERSION` hangs (`DAP ACK` timeout) or returns `0x00000000` | Zynq PS-PL isolation bridges still locked, or `clk_wiz` unlocked | Run full XSDB sequence (`psu_init`, `psu_post_config`, `psu_ps_pl_isolation_removal`, `psu_ps_pl_reset_config`) or check `clk_wiz/locked` |
| Writing `COEFF` / 16-bit registers appears ignored | Partial byte strobe (`wstrb`) masked out write | Always perform aligned 32-bit writes (`wstrb = 4'hF`) |
| First `N-1` samples after runtime profile switch show transient mismatch | Reset-free SRL delay line still holds previous run's tail | Flush `<TAPS - 1>` zero samples (or assert valid-gating flush) after updating coefficients |
| `create_bd_cell -type module` fails on SV ports | Vivado IPI cannot parse SV packages or unpacked/2D ports on module references | Instantiate the pure Verilog-2001 `*_bd_wrapper.v` |
| Synthesis emits missing-clock critical warnings or OOC build fails on async CDC XDC | `set_clock_groups` referencing BD pins ran during OOC synthesis | Tag `impl_cdc.xdc` with `set_property USED_IN {implementation}` |
