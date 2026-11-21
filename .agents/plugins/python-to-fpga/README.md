# Python-to-FPGA Bitstream Plugin (`python-to-fpga`)

This Antigravity plugin packages **Path 2 (SPEC.md Requirements -> Python Golden Reference -> Direct Synthesizable SystemVerilog -> Vivado Verification -> FPGA Bitstream)** with always-on discipline guardrails and a structured lessons-learned catalog so AI agents do not waste hours debugging RTL in Place & Route.

## What Is Inside

- **[rules/AGENTS.md](rules/AGENTS.md)** — Always-on rules enforcing Stage 0 `SPEC.md` agreement before Stage 1, Stage 1 Python Golden approval before HDL authoring, fast-loop (`2B` lint / `2C` unit XSim) vs. slow-gate (`2D` / `2E` / `2F`) discipline, and clean-repo hygiene.
- **[skills/python-to-bitstream/SKILL.md](skills/python-to-bitstream/SKILL.md)** — On-demand execution runbook with exact pass/fail criteria across Stages 0 through 2F.
- **[skills/python-to-bitstream/references/spec_template.md](skills/python-to-bitstream/references/spec_template.md)** — Collaborative Stage 0 `SPEC.md` requirements template & sign-off checklist.
- **[skills/python-to-bitstream/references/lessons_learned.md](skills/python-to-bitstream/references/lessons_learned.md)** — 13 real failure modes from ZCU102 hardware sign-off (`Trigger -> Failure -> Preventive Pattern -> Check`).
- **[skills/python-to-bitstream/references/vivado_recipes.md](skills/python-to-bitstream/references/vivado_recipes.md)** — Copy-pasteable Tcl, Verilog-2001 IPI wrappers, `USED_IN implementation` CDC XDCs, and XSDB JTAG sequences.
- **[skills/python-to-bitstream/scripts/scaffold_block.py](skills/python-to-bitstream/scripts/scaffold_block.py)** — Stdlib-only Python generator for scaffolding new DSP blocks from Stage 1 to Stage 2C.

## Prerequisites

- **Python 3.10+** (standard library only for templates)
- **AMD Vivado / XSDB** (`2024.x–2026.x`, invoked via batch CLI scripts or optional `vivado` / `vivado-doc-search` MCP servers)

## Installation

### Antigravity (Per-Repository)
Place this folder at `<repo>/.agents/plugins/python-to-fpga/`. It loads automatically when opening the workspace.

### Antigravity (Global — All Projects)
Copy this folder to `~/.gemini/config/plugins/python-to-fpga/`:
- **PowerShell:** `Copy-Item -Recurse -Force ".agents\plugins\python-to-fpga" "$env:USERPROFILE\.gemini\config\plugins\python-to-fpga"`
- **Bash:** `cp -r .agents/plugins/python-to-fpga ~/.gemini/config/plugins/python-to-fpga`

### Other AI Coding CLIs (Skill Only)
Copy `skills/python-to-bitstream/` to `.claude/skills/`, `.agents/skills/`, `.gemini/skills/`, or `.opencode/skills/`.
