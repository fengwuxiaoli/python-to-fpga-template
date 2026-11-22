# Project Rules — Python-to-FPGA Template Repository

This repository implements **Path 2 (SPEC.md Requirements -> Python Golden Reference -> Synthesizable SystemVerilog RTL -> Vivado Verification -> FPGA Bitstream)** with a runnable 15-tap symmetric FIR canary block (`canary_fir`).

## Project Defaults
- **Target Device (`PART`):** `xczu9eg-ffvb1156-2-e` (AMD Zynq UltraScale+ ZCU102 default)
- **Board Part (`BOARD_PART`):** `xilinx.com:zcu102:part0:3.4`
- **Target Clock (`TARGET_CLK_MHZ`):** `245.761` MHz (4.069 ns period)
- **Central Configuration:** [vivado/board_config.tcl](vivado/board_config.tcl) (override via `FPGA_PART`, `FPGA_BOARD_PART`, `FPGA_CLK_MHZ`, and `FPGA_BUILD_DIR`)

## Workspace Layout
- `SPEC.md` — Stage 0 requirements specification (collaboratively agreed & approved before Stage 1; pre-filled for `canary_fir`, see [SPEC.md](SPEC.md))
- `INTEGRATION.md` — Stage 2F deliverable storage policy plus Software/SoC & FPGA RTL integration guide (see [INTEGRATION.md](INTEGRATION.md))
- `python/` — Floating-point + bit-exact fixed-point golden models and `.mem` vector generators
- `rtl/` — Synthesizable SystemVerilog modules (`axis_skid`, `canary_fir_regs`, `canary_fir_core`, `canary_fir_top`)
- `tb/` — Self-checking SystemVerilog XSim testbenches
- `test_vectors/` — Hex `.mem` stimulus, coefficients, and golden expected vectors (`$readmemh`)
- `sim/` — Batch/shell lint (`run_lint.*`) and XSim co-simulation runners (`run_sim_*.*`)
- `vivado/` — Parameterized Tcl, Verilog-2001 IPI wrappers, XDC timing/CDC constraints, and checkpointed bitstream builders
- `sw/` — C99 and Python register map headers (`canary_fir_regs.h`, `canary_fir_regs.py`) for Vitis/PetaLinux/PYNQ integration
- `bringup/` — XSDB JTAG bring-up scripts and Phase 1 / Phase 2 bench verification guides
- `docs/` — Engineering playbook ([docs/PLAYBOOK.md](docs/PLAYBOOK.md))

## Agent Workflow & Guardrails
The full **Stage 0 through Stage 2F** workflow rules, fast-loop vs. slow-gate discipline, repository hygiene rules, and lessons learned live in the bundled Antigravity plugin:
- **Always-on rules:** [.agents/plugins/python-to-fpga/rules/AGENTS.md](.agents/plugins/python-to-fpga/rules/AGENTS.md)
- **Step-by-step runbook:** [.agents/plugins/python-to-fpga/skills/python-to-bitstream/SKILL.md](.agents/plugins/python-to-fpga/skills/python-to-bitstream/SKILL.md)

Every new block or design change starts in **Stage 0**: co-author `SPEC.md` (from `.agents/plugins/python-to-fpga/skills/python-to-bitstream/references/spec_template.md`) and wait for explicit agreement on all items before entering Stage 1. Antigravity discovers `.agents/plugins/python-to-fpga/` automatically. If you are using another AI coding tool, read the two files linked above before designing or modifying any DSP/RTL block.
