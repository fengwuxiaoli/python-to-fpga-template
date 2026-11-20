# Python-to-FPGA Bitstream Template & Agent Plugin

A ready-to-use **GitHub Template Repository** + **Antigravity Plugin** (`python-to-fpga`) implementing **Path 2: Python Golden Reference -> Synthesizable SystemVerilog RTL -> Vivado Verification -> FPGA Bitstream**.

Originally battle-tested while delivering a timing-closed 5G NR O-RAN vDU bitstream on AMD Zynq UltraScale+ (`ZCU102 xczu9eg`, `245.761 MHz`, 10GBASE-R XGMII + 8-lane JESD204C TX), this template extracts the domain-agnostic engineering workflow, Vivado Tcl/XDC recipes, and pitfalls catalog into a clean starter kit with a **runnable 15-tap symmetric FIR canary block (`canary_fir`)**.

> **Human Playbook:** Read [docs/PLAYBOOK.md](docs/PLAYBOOK.md) for the full stage-by-stage workflow, architecture flowchart, and Phase 1 / Phase 2 bring-up methodology.  
> **Lessons Learned Catalog:** Read [lessons_learned.md](.agents/plugins/python-to-fpga/skills/python-to-bitstream/references/lessons_learned.md) to avoid the 13 most expensive Python-to-Vivado traps before writing RTL.

---

## Use This Template — Quick Start

### 1. Prerequisites
- **Python 3.10+** (verified on Python 3.15 — the canary uses Python's standard library only; zero `pip install` needed).
- **AMD Vivado** (`2024.x–2026.x`, verified with Vivado 2026.1 on `xczu9eg-ffvb1156-2-e`).
  - Windows batch scripts honor `VIVADO_BIN` (default `C:\AMDDesignTools\2026.1\Vivado\bin`).
  - Linux/macOS shell scripts use `VIVADO_BIN` or `vivado` on `PATH`.
- **Optional MCP Servers (recommended in Antigravity):** `vivado` and `vivado-doc-search` for live doc lookup and interactive Tcl execution.

### 2. Run the Canary Block End-to-End

Run these commands from the repository root (zero temporary `.log`/`.jou`/`xsim.dir` clutter is left behind):

```powershell
# Stage 1: Verify floating-point vs. bit-exact fixed-point Python model (~0.1 s)
py python/canary_fir_golden.py

# Stage 1: Generate $readmemh stimulus, coefficient, and golden expected .mem vectors
py python/generate_canary_vectors.py

# Stage 2B: Fast RTL + Verilog-2001 wrapper syntax & Vivado synth_design -lint (< 1 min)
sim\run_lint.bat                  # Linux/macOS: ./sim/run_lint.sh

# Stage 2C: Vivado XSim bit-exact co-simulation across 4 AXI-Lite/Stream scenarios (< 30 s)
sim\run_sim_canary.bat            # Linux/macOS: ./sim/run_sim_canary.sh

# Stage 2E-1: Out-of-Context (OOC) block synthesis budget at 245.761 MHz (~30-60 s)
C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog -source vivado/run_ooc_synth.tcl
```

To run the full Zynq MPSoC Block Design synthesis, P&R, and `.bit` + fixed `.xsa` generation (**Stage 2E-2 -> 2E-3 -> 2F**, builds into `%TEMP%/python_to_fpga_canary` or `$env:FPGA_BUILD_DIR`):

```powershell
vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs synth
vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs impl
vivado -mode batch -nojournal -nolog -source vivado/build_bitstream.tcl -tclargs bitstream
```

### Canary Verification Baseline (Verified on Vivado 2026.1 / `xczu9eg-ffvb1156-2-e`)

| Stage | Target / Command | Verified Result |
| :--- | :--- | :--- |
| **Stage 1** | `python/canary_fir_golden.py` + `generate_canary_vectors.py` | PASS (`DC=-0.0003 dB`, `Stop=-56.93 dB`, `Nyq=-45.85 dB`, `Float-vs-Fixed MaxErr=0.5000 LSB`, 5 `.mem` files) |
| **Stage 2B** | `sim/run_lint.bat` (`xvlog -sv` + `synth_design -lint`) | PASS (`0` errors, `0` critical warnings, `0` linter violations across RTL + BD wrapper) |
| **Stage 2C** | `sim/run_sim_canary.bat` (4 scenarios, bubbles + backpressure) | `ALL TESTS PASSED (0 ERRORS)` (`VERSION=0x46495231`, 256 default, 256 custom AXI-Lite, 32 bypass) |
| **Stage 2E-1** | `vivado/run_ooc_synth.tcl` @ `245.761 MHz` (`T=4.069 ns`) | `WNS=+0.525 ns`, `WHS=+0.039 ns`, `WPWS=+1.502 ns` (`178` CLB LUTs = `162` logic + `16 SRL16E`, `447` FFs, `10 DSP48E2`, `0` latches) |

---

## Reusing the Bundled Agent Plugin

This template ships an Antigravity Plugin at [`.agents/plugins/python-to-fpga/`](.agents/plugins/python-to-fpga/) containing always-on Stage 1–2F guardrails (`rules/AGENTS.md`), the step-by-step skill (`SKILL.md`), references (`lessons_learned.md`, `vivado_recipes.md`), and a new-block generator (`scaffold_block.py`).

### Option A — Antigravity (Automatic Per-Repository)
Clone or instantiate this template and open it in Antigravity. Workspace plugins under `.agents/plugins/` are discovered automatically—no setup required.

### Option B — Antigravity (Install Globally for All Future Projects)
Copy the plugin directory into your global Antigravity config folder:
- **Windows (PowerShell):**
  ```powershell
  Copy-Item -Recurse -Force ".agents\plugins\python-to-fpga" "$env:USERPROFILE\.gemini\config\plugins\python-to-fpga"
  ```
- **Linux / macOS:**
  ```bash
  cp -r .agents/plugins/python-to-fpga ~/.gemini/config/plugins/python-to-fpga
  ```

### Option C — Other AI Coding CLIs (Portable Skill Only)
Copy `.agents/plugins/python-to-fpga/skills/python-to-bitstream/` into your tool's skill directory:
- **Claude Code:** `.claude/skills/python-to-bitstream/` (or `~/.claude/skills/`)
- **Codex:** `.agents/skills/python-to-bitstream/` (or `~/.agents/skills/`)
- **Gemini CLI:** `.gemini/skills/python-to-bitstream/` (or `~/.gemini/skills/`)
- **OpenCode:** `.opencode/skills/python-to-bitstream/` (or `~/.config/opencode/skills/`)

### Scaffolding Your Own DSP Block
Use the bundled CLI helper to generate Stage 1 golden, vector exporter, Stage 2A SV starter, Stage 2C testbench, and XSim scripts in one step:

```powershell
py .agents/plugins/python-to-fpga/skills/python-to-bitstream/scripts/scaffold_block.py --block my_dsp --repo . --magic MDSP
```

---

## Repository Structure

```text
python-to-fpga-template/
├── .agents/plugins/python-to-fpga/   # Turnkey Antigravity Plugin + portable skill & lessons learned
│   ├── plugin.json
│   ├── README.md
│   ├── assets/logo.svg
│   ├── rules/AGENTS.md               # Always-on Stage 1-2F fast-loop & hygiene rules
│   └── skills/python-to-bitstream/
│       ├── SKILL.md
│       ├── references/
│       │   ├── lessons_learned.md    # 13 real Stage 1->2F failure modes & preventive checks
│       │   └── vivado_recipes.md     # Copy-pasteable Tcl, IPI wrapper, XDC, XSDB recipes
│       └── scripts/scaffold_block.py # Starter generator for new DSP blocks
├── AGENTS.md                         # Repo defaults (part/clock) + pointer to plugin
├── README.md
├── .gitignore                        # Ignores Vivado/XSim logs, checkpoints, .bit, .xsa, figures
├── docs/
│   └── PLAYBOOK.md                   # Human Stage 1->2F playbook & board adaptation guide
├── python/
│   ├── canary_fir_golden.py          # Float + bit-exact fixed-point 15-tap symmetric FIR model
│   └── generate_canary_vectors.py    # 256-sample Q1.15 stimulus & golden .mem vector exporter
├── rtl/
│   ├── axis_skid.sv                  # Registered 2-entry AXI4-Stream skid buffer
│   ├── canary_fir_regs.sv            # AXI4-Lite slave (VERSION=0x46495231 "FIR1", CTRL, STATUS, COEFF[0..7])
│   ├── canary_fir_core.sv            # Reset-free SRL delay line + symmetric DSP48E2 FIR pipeline
│   └── canary_fir_top.sv             # Integrates regs + core
├── tb/
│   └── tb_canary_fir.sv              # Self-checking TB (VERSION, default, AXI-Lite custom coeffs, bypass)
├── test_vectors/                     # Committed $readmemh golden .mem files
├── sim/
│   ├── run_lint.bat / run_lint.sh    # Stage 2B xvlog + Vivado synth_design -lint
│   └── run_sim_canary.bat / .sh      # Stage 2C XSim bit-exact runner + artifact cleanup
├── vivado/
│   ├── board_config.tcl              # Centralized PART / BOARD_PART / TARGET_CLK_MHZ / BUILD_DIR
│   ├── canary_fir_bd_wrapper.v       # Verilog-2001 IPI wrapper with X_INTERFACE_INFO attributes
│   ├── run_lint.tcl                  # Stage 2B in-memory Vivado lint
│   ├── run_ooc_synth.tcl             # Stage 2E-1 OOC resource/timing budget
│   ├── constraints.xdc               # Synthesis + implementation physical/clock constraints template
│   ├── impl_cdc.xdc                  # USED_IN {implementation} async CDC & reset fanout template
│   ├── create_bd.tcl                 # Parameterized Zynq MPSoC + ClkWiz + SmartConnect + AXI DMA BD
│   └── build_bitstream.tcl           # Stage 2E-2/2E-3/2F tiered checkpoint build (synth/impl/bitstream)
└── bringup/
    ├── jtag_bringup.tcl              # XSDB JTAG XSA extraction, psu_init, isolation removal, VERSION check
    └── README_BRINGUP.md             # Phase 1 standalone vs. Phase 2 bench verification checklist
```
