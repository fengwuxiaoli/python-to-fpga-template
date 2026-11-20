# Hardware Bring-Up Guide (Phase 1 -> Phase 2)

Never debug PL datapath logic, PS-PL bridges, and external SerDes/RF cables at the same time. Follow this two-phase bench protocol after **Stage 2E-3** timing closure and **Stage 2F** bitstream/`.xsa` export.

---

## Phase 1 — Standalone Board Smoke Test (No External I/O Required)

**Goal:** Prove PS initialization, `clk_wiz` lock, PS-PL isolation removal, AXI4-Lite register read/write, and self-contained AXI DMA loopback on an isolated board (power + JTAG USB + UART USB only).

### 1. Pre-Flight Checklist
- Set board boot mode switches to **JTAG boot** (`SW6 = 0000` / all OFF on ZCU102).
- Connect JTAG USB and UART USB to the host PC.
- Ensure you built the fixed XSA with embedded bitstream (`vivado/build_bitstream.tcl -tclargs bitstream` -> `write_hw_platform -fixed -include_bit`).

### 2. Run XSDB Bring-Up
```powershell
xsdb bringup/jtag_bringup.tcl
# Or specify explicit XSA/base address:
xsdb bringup/jtag_bringup.tcl C:\path\to\canary_fir.xsa 0xA0000000
```

**Expected Output:**
- `psu_init` -> `fpga -no-revision-check` -> `psu_post_config` -> `psu_ps_pl_isolation_removal` -> `psu_ps_pl_reset_config` completes cleanly.
- `VERSION (0x00) = 0x46495231 ("FIR1")`
- `CTRL (0x04)` toggles `1 -> 0`
- `COEFF[7] (0x2C) = 0x00001923 (6435)`

> [!WARNING]
> If `mrd` hangs or returns bus fault/zeros, confirm `jtag_bringup.tcl` ran **both** `psu_init` **and** `psu_ps_pl_isolation_removal`. Running `fpga -f` alone leaves PS-PL level shifters locked (Lesson L13).

### 3. Optional AXI DMA Loopback (PS DDR <-> PL FIR)
Using the `axi_dma` wired in [`vivado/create_bd.tcl`](../vivado/create_bd.tcl), allocate two buffers in DDR (`stim` and `rx`), kick MM2S (`stim`) and S2MM (`rx`), and compare the returned buffer sample-for-sample against `python/canary_fir_golden.py::fir_fixed()`.

---

## Phase 2 — Full System / External I/O Bench Test

Only start Phase 2 **after Phase 1 passes cleanly**:

1. Connect external clock references (e.g., 10 MHz / 156.25 MHz / 245.76 MHz `SYSREF` or FMC/SFP+ transceivers).
2. Add physical pin LOC / IOSTANDARD constraints to [`vivado/constraints.xdc`](../vivado/constraints.xdc) and GTH/GTY async clock groups to [`vivado/impl_cdc.xdc`](../vivado/impl_cdc.xdc).
3. Verify transceiver PLL lock and link status telemetry bits via AXI4-Lite/GPIO before evaluating DSP metrics (ACLR, EVM, SNR) on external bench analyzers.
