# Hardware Block / Project Requirements Specification (`SPEC.md`)

> **Stage 0 Collaborative Agreement Gate:**  
> Copy this template to `SPEC.md` at the repository root and co-author every section with the user before starting **Stage 1 (Python Golden Reference)** or writing any HDL (`Stage 2A`).  
> **Hard Rule:** Do **not** proceed to Stage 1 (`python/*_golden.py`, `.mem` vector generation, or `scaffold_block.py`) until `0` open questions remain, all checklist items below are marked `[x]`, and `Status` is set to `APPROVED` by explicit user agreement.

---

## Document Control

| Field | Value |
| :--- | :--- |
| **Block / Project Name** | `<block_snake_case>` |
| **Version** | `0.1` |
| **Status** | `DRAFT` *(must transition `DRAFT` -> `IN REVIEW` -> `APPROVED` before Stage 1)* |
| **Owner(s)** | `<User / Hardware Engineer & AI Agent>` |
| **Date** | `<YYYY-MM-DD>` |
| **Target Part / Board** | `<e.g., xczu9eg-ffvb1156-2-e / xilinx.com:zcu102:part0:3.4>` *(see `vivado/board_config.tcl`)* |

---

## Stage 0 Sign-Off Gate & Agreement Checklist

**Stage 1 (Python Golden Reference) and Stage 2 (RTL/Vivado) MUST NOT start until every box below is `[x]` agreed and `Status: APPROVED`:**

- [ ] **1. Scope, Goals & Non-Goals agreed** (Section 1)
- [ ] **2. Target Platform, Clocking, Reset Policy & Resource Budgets agreed** (Section 2)
- [ ] **3. Algorithm, Operating Modes & Edge-Case Behavior agreed** (Section 3)
- [ ] **4. Fixed-Point Architecture, Rounding, Saturation & Numerical Targets agreed** (Section 4)
- [ ] **5. Hardware Interfaces & AXI4-Lite Register Map (including `0x00 VERSION`) agreed** (Section 5)
- [ ] **6. Verification & Acceptance Criteria (Stage 1 -> Stage 2F) agreed** (Section 6)
- [ ] **7. All Open Questions & Assumptions resolved (`0` `OPEN` items)** (Section 7)

> **Change Control:** If Stage 1 fixed-point exploration or Stage 2 implementation reveals a required change to bit widths, latency, register offsets, or pass/fail thresholds, update `SPEC.md` and re-confirm agreement with the user before updating downstream code.

---

## 1. Scope, Goals & Non-Goals

### 1.1 Problem Statement & Functional Goal
- `<Describe what the block/subsystem computes, why it exists, and how it fits into the overall system.>`

### 1.2 In-Scope Deliverables
- **Stage 1:** Floating-point + bit-exact fixed-point Python reference (`python/<block>_golden.py`) and `$readmemh` vector generator (`python/generate_<block>_vectors.py`).
- **Stage 2A–2D:** Synthesizable SystemVerilog RTL (`rtl/*.sv`), Verilog-2001 IPI wrapper (`vivado/*_bd_wrapper.v`), lint scripts, and self-checking XSim testbench (`tb/tb_<block>.sv`).
- **Stage 2E–2F:** OOC synthesis budget, Block Design / XDC integration, P&R timing closure, bitstream + fixed `.xsa`, and hardware bring-up scripts (`bringup/`).

### 1.3 Explicit Non-Goals (Out of Scope)
- `<List features, protocols, modes, or optimizations explicitly excluded from this milestone.>`

---

## 2. Target Platform, Clocking, Reset Policy & Resource Budgets

| Parameter | Agreed Requirement | Notes / Reference |
| :--- | :--- | :--- |
| **Target FPGA Part (`FPGA_PART`)** | `<e.g., xczu9eg-ffvb1156-2-e>` | Override in `vivado/board_config.tcl` or env |
| **Board Part (`FPGA_BOARD_PART`)** | `<e.g., xilinx.com:zcu102:part0:3.4>` | `""` if bare part without board repo |
| **Primary PL Clock (`FPGA_CLK_MHZ`)** | `<e.g., 245.761 MHz (4.069 ns)>` | Derived from `clk_wiz` / dynamic `ps8/pl_clk0` |
| **Additional Clocks & CDC Boundaries** | `<e.g., PS pl_clk0 (~99.99 MHz) <-> PL core>` | Async crossings isolated in `vivado/impl_cdc.xdc` (`USED_IN implementation`) |
| **Reset Policy** | `<Sync active-low rst_n on control/valid & AXI-Lite; reset-free datapath & SRLs>` | Enables `SRL16E`/`SRLC32E` and `DSP48E2` `AREG`/`MREG`/`PREG` packing |
| **Throughput (`II`) & Sample Rate** | `<e.g., II = 1 sample/cycle @ 245.761 MSPS>` | Specify TDM folding factor (`II = N`) if multi-channel |
| **Latency Budget** | `<e.g., <= 5 clock cycles core + output skid>` | Measured valid-in to valid-out under `m_axis_tready = 1` |
| **Resource Budget (LUT / FF / DSP48E2 / BRAM)** | `<e.g., <= 500 LUTs, <= 10 DSP48E2, 0 BRAM>` | Checked early in Stage 2E-1 OOC synthesis |

---

## 3. Algorithm & Mathematical Specification

### 3.1 Mathematical Definition / Transfer Function
- `<Write exact equations, filter order/taps, FFT length, CORDIC iterations, packet state machine, or DSP dataflow.>`

### 3.2 Operating Modes
- **Normal Mode:** `<Default processing behavior.>`
- **Bypass / Passthrough Mode (`CTRL[0]`):** `<Describe bypass path, latency alignment if required, and overflow flag suppression.>`
- **Runtime Reconfiguration:** `<Describe whether coefficients/parameters can change at runtime and whether a zero-flush or state reset is required.>`

### 3.3 Framing, Startup & Edge-Case Behavior
- **Initial / Power-On State:** `<Zeroed reset-free data history; initial valid state.>`
- **`TLAST` Propagation:** `<Sample-aligned pipeline propagation; burst boundaries.>`
- **Flush / Drain Policy:** `<Pipeline advances on pipe_en = !core_tvalid || core_tready so tail samples drain cleanly even when s_axis_tvalid deasserts.>`

---

## 4. Fixed-Point Architecture & Numerical Requirements

### 4.1 Bit-Width & Q-Format Table

| Signal / Stage | Signedness | Width & Q-Format | Range / Guard Bits | Notes |
| :--- | :---: | :---: | :---: | :--- |
| **Input (`s_axis_tdata`)** | `Signed` | `<e.g., 16-bit Q1.15>` | `[-32768, 32767]` | `<e.g., 2's complement>` |
| **Coefficients / Parameters** | `Signed` | `<e.g., 16-bit Q1.15>` | `[-32768, 32767]` | `<Static or AXI4-Lite programmable>` |
| **Pre-Adder / Intermediate** | `Signed` | `<e.g., 17-bit Q2.15>` | `<Guard bit for symmetric sum>` | `<No overflow possible>` |
| **Multiplier Product** | `Signed` | `<e.g., 33-bit Q3.30>` | `DSP48E2 MREG` | `<Reset-free>` |
| **Accumulator** | `Signed` | `<e.g., 38-bit>` | `<No wrap on worst-case input>` | `<Explicit sign extension>` |
| **Output (`m_axis_tdata`)** | `Signed` | `<e.g., 16-bit Q1.15>` | `[-32768, 32767]` | `<Post-rounding & saturation>` |

### 4.2 Rounding, Saturation & Python-to-SV Bit-Exact Parity
- **Rounding Mode:** `<e.g., Round half-up via arithmetic right shift: Python (acc + (1 << (F - 1))) >> F matching SV (acc + (1 <<< (F - 1))) >>> F>`
- **Overflow / Saturation Policy:** `<e.g., Clamp to [-(2^(W-1)), 2^(W-1)-1]; pulse ovf_pulse_o on clamp; latch sticky STATUS[0] until W1C>`
- **`.mem` Export Format:** `<Hex 2's complement masked to exact width: val & ((1 << W) - 1)>`

### 4.3 Quantitative Acceptance Targets

| Metric | Pass Threshold | Test Stimulus / Condition |
| :--- | :--- | :--- |
| **Passband / DC Gain** | `<e.g., |Gain| < 0.01 dB>` | `<Tone / DC sweep>` |
| **Stopband / Attenuation / EVM / ACLR** | `<e.g., Stopband < -35 dB, Nyq < -40 dB>` | `<Frequency response / waveform test>` |
| **Float vs. Fixed-Point Max Error** | `<e.g., <= 0.51 LSB>` | `<Composite multi-tone + impulse + rails>` |
| **Saturation / Overflow Test** | `<Clamps cleanly & asserts ovf_flag > 0>` | `<Overdrive full-scale stimulus>` |

---

## 5. Hardware Interfaces & Register Map

### 5.1 Port & Streaming Interfaces
- **Clock & Reset:** `clk` (rising edge), `rst_n` (synchronous active-low).
- **AXI4-Stream Slave (`s_axis`):** `tdata` (`<width>`), `tvalid`, `tready`, `tlast`.
- **AXI4-Stream Master (`m_axis`):** `tdata` (`<width>`), `tvalid`, `tready`, `tlast`, buffered through a 2-entry registered `axis_skid` to break combinational `tready` loops.
- **Sideband / Telemetry Ports:** `<e.g., ovf_sticky_o status output>`.
- **IPI Wrapper:** Pure Verilog-2001 `vivado/<block>_bd_wrapper.v` with `X_INTERFACE_INFO` / `X_INTERFACE_PARAMETER` attributes (1D ports only).

### 5.2 AXI4-Lite Register Map
- **Bus Geometry:** 32-bit data (`WSTRB` honored), `<e.g., 8-bit>` byte address, `<e.g., base 0xA0000000 in IPI BD>`.

| Offset | Name | Access | Reset Value | Bit Fields & Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `VERSION` | `RO` | `0x<4-char ASCII hex>` | Fixed 4-byte ASCII magic ID for Phase 1 JTAG/PS liveness (`0x00` mandatory) |
| `0x04` | `CTRL` | `RW` | `0x00000000` | `[0]`: `bypass_en` (`1` = bypass, `0` = normal); `[31:1]` reserved (`0`) |
| `0x08` | `STATUS` | `R/W1C` | `0x00000000` | `[0]`: `ovf_sticky` (latched on overflow, write `1` to clear) |
| `0x10..` | `<CUSTOM_REGS>` | `<RW/RO>` | `<Reset>` | `<Define block-specific coefficient/parameter registers>` |

---

## 6. Verification & Acceptance Criteria (Stage 1 -> Stage 2F)

| Stage | Verification Scope | Mandatory Pass Criteria |
| :--- | :--- | :--- |
| **Stage 1 (Python)** | `python/<block>_golden.py` + `generate_<block>_vectors.py` | Float vs. fixed metrics meet Section 4.3; `.mem` vectors generated; **explicit user sign-off before Stage 2A** |
| **Stage 2B (Lint)** | `xvlog -sv` + Vivado `synth_design -lint` (RTL + `*_bd_wrapper.v`) | Exit code `0`, `0` inferred latches, `0` multi-driven nets, `0` width mismatches |
| **Stage 2C (Unit XSim)** | `tb/tb_<block>.sv` against `.mem` vectors | `0` bit mismatches across `VERSION`/reset checks, random `tvalid` bubbles + `tready` backpressure, runtime AXI4-Lite reconfig, and bypass mode |
| **Stage 2D (Top XSim)** | Full-chain integration smoke & soak | `100%` of 2B/2C passed; `0` end-to-end mismatches (`tlast` & sample exact) |
| **Stage 2E (Synth & P&R)** | OOC budget (`2E-1`) + BD synth (`2E-2`) + P&R (`2E-3`) | Expected `DSP48E2`/`SRL`/`BRAM` inference; post-route `WNS >= 0 ns`, `TNS = 0 ns`, `WHS >= 0 ns`, `THS = 0 ns`, `WPWS >= 0 ns`, `0` DRC/routing errors |
| **Stage 2F (Bring-Up)** | Bitstream + fixed `.xsa` + XSDB `jtag_bringup.tcl` | **Phase 1:** `psu_init` + isolation removal + `VERSION` readback + register/DMA loopback pass; **Phase 2:** external I/O / RF / PHY bench criteria met |

---

## 7. Open Questions & Assumptions Log

> **Gate Rule:** Every row below MUST reach `Status: RESOLVED` before Stage 0 can be marked `APPROVED`.

| ID | Topic | Question / Assumption | Resolution | Status |
| :---: | :--- | :--- | :--- | :---: |
| `Q1` | `<Topic>` | `<Question or tentative assumption requiring user decision>` | `<Pending discussion>` | `OPEN` |
