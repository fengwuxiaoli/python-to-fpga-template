#!/usr/bin/env python3
"""Scaffold a new DSP block across Stage 1 (Python) -> Stage 2A (SV) -> Stage 2C (XSim).

Run only after Stage 0 (`SPEC.md`) is agreed and approved.

Creates:
  python/<block>_golden.py
  python/generate_<block>_vectors.py
  rtl/<block>.sv
  tb/tb_<block>.sv
  sim/run_sim_<block>.bat
  sim/run_sim_<block>.sh

Uses Python standard library only. Never overwrites existing files unless --force is passed.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


GOLDEN_TEMPLATE = '''"""Stage 1 Python Golden Reference for `{block}`.

Implements agreed requirements in `SPEC.md` (Stage 0).
"""

from __future__ import annotations


def model_float(samples: list[int]) -> list[float]:
    """Floating-point behavioral model (implement algorithm here)."""
    return [float(s) / 32768.0 for s in samples]


def model_fixed(samples: list[int]) -> list[int]:
    """Bit-exact Q1.15 fixed-point reference matching `rtl/{block}.sv`."""
    outputs: list[int] = []
    for s in samples:
        val = max(-32768, min(32767, int(s)))
        outputs.append(val)
    return outputs


def main() -> int:
    stim = [0, 8192, -8192, 16384, -16384, 32767, -32768]
    flt = model_float(stim)
    fix = model_fixed(stim)
    max_err = max(abs(f - (x / 32768.0)) for f, x in zip(flt, fix))
    print(f"[{block}] Stage 1 golden PASS: samples={{len(stim)}}, max_err={{max_err:.3e}}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


VECTORS_TEMPLATE = '''"""Generate $readmemh stimulus and expected vectors for `{block}`."""

from __future__ import annotations

import math
from pathlib import Path

from {block}_golden import model_fixed


def write_hex16(path: Path, values: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\\n") as f:
        for v in values:
            f.write(f"{{v & 0xFFFF:04X}}\\n")


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    vec_dir = repo / "test_vectors"
    n = 128
    stim = [int(round(16384.0 * math.sin(2.0 * math.pi * 5.0 * i / n))) for i in range(n)]
    exp = model_fixed(stim)

    stim_path = vec_dir / "{block}_stim.mem"
    exp_path = vec_dir / "{block}_exp.mem"
    write_hex16(stim_path, stim)
    write_hex16(exp_path, exp)
    print(f"[{block}] Generated {{n}} vectors -> {{stim_path}} & {{exp_path}}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


RTL_TEMPLATE = '''// ==============================================================================
// Stage 2A Synthesizable SystemVerilog Starter for `{block}`
// Implements agreed requirements in SPEC.md (Stage 0) and python/{block}_golden.py (Stage 1).
// Remember Lessons Learned:
//   - Keep data pipelines/SRL chains reset-free (`= '{{default: '0}}`).
//   - Put `rst_n` only on valid/control registers and AXI4-Lite registers.
//   - Provide read-only VERSION register at offset 0x00 for Phase 1 JTAG checks.
// ==============================================================================
`timescale 1ns / 1ps

module {block} #(
  parameter logic [31:0] VERSION_ID = 32'h{magic_hex} // "{magic}"
)(
  input  logic        clk,
  input  logic        rst_n,

  // Minimal AXI4-Lite Control Interface (VERSION @ 0x00, CTRL @ 0x04)
  input  logic [7:0]  s_axil_awaddr,
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  output logic [1:0]  s_axil_bresp,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,

  input  logic [7:0]  s_axil_araddr,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,

  // AXI4-Stream 16-bit Sample Data Interface
  input  logic signed [15:0] s_axis_tdata,
  input  logic               s_axis_tvalid,
  output logic               s_axis_tready,
  input  logic               s_axis_tlast,

  output logic signed [15:0] m_axis_tdata,
  output logic               m_axis_tvalid,
  input  logic               m_axis_tready,
  output logic               m_axis_tlast
);

  // AXI4-Lite single-beat write/read FSM
  logic       aw_seen, w_seen;
  logic [7:0] aw_addr_q;
  logic [31:0] w_data_q;
  logic [3:0] w_strb_q;
  logic       ctrl_bypass_q;

  assign s_axil_awready = !aw_seen && !s_axil_bvalid;
  assign s_axil_wready  = !w_seen  && !s_axil_bvalid;
  assign s_axil_bresp   = 2'b00;
  assign s_axil_arready = !s_axil_rvalid;
  assign s_axil_rresp   = 2'b00;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_seen       <= 1'b0;
      w_seen        <= 1'b0;
      aw_addr_q     <= 8'd0;
      w_data_q      <= 32'd0;
      w_strb_q      <= 4'd0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata  <= 32'd0;
      ctrl_bypass_q <= 1'b0;
    end else begin
      if (s_axil_awvalid && s_axil_awready) begin
        aw_seen   <= 1'b1;
        aw_addr_q <= s_axil_awaddr;
      end
      if (s_axil_wvalid && s_axil_wready) begin
        w_seen   <= 1'b1;
        w_data_q <= s_axil_wdata;
        w_strb_q <= s_axil_wstrb;
      end
      if ((aw_seen || (s_axil_awvalid && s_axil_awready)) &&
          (w_seen  || (s_axil_wvalid  && s_axil_wready))  && !s_axil_bvalid) begin
        automatic logic [7:0]  wr_addr = aw_seen ? aw_addr_q : s_axil_awaddr;
        automatic logic [31:0] wr_data = w_seen  ? w_data_q  : s_axil_wdata;
        automatic logic [3:0]  wr_strb = w_seen  ? w_strb_q  : s_axil_wstrb;
        if (wr_addr == 8'h04 && wr_strb[0]) begin
          ctrl_bypass_q <= wr_data[0];
        end
        aw_seen       <= 1'b0;
        w_seen        <= 1'b0;
        s_axil_bvalid <= 1'b1;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_rvalid <= 1'b1;
        case (s_axil_araddr)
          8'h00:   s_axil_rdata <= VERSION_ID;
          8'h04:   s_axil_rdata <= {{31'd0, ctrl_bypass_q}};
          default: s_axil_rdata <= 32'd0;
        endcase
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

  // Sample pipeline (valid/last reset by rst_n; data register reset-free)
  logic pipe_en;
  logic signed [15:0] data_q = 16'sd0;

  assign pipe_en       = !m_axis_tvalid || m_axis_tready;
  assign s_axis_tready = pipe_en;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
    end else if (pipe_en) begin
      m_axis_tvalid <= s_axis_tvalid;
      m_axis_tlast  <= s_axis_tlast;
    end
  end

  always_ff @(posedge clk) begin
    if (pipe_en && s_axis_tvalid) begin
      data_q <= s_axis_tdata;
    end
  end

  assign m_axis_tdata = data_q;

endmodule
'''


TB_TEMPLATE = '''`timescale 1ns / 1ps

module tb_{block};
  localparam int N = 128;

  logic clk = 1'b0;
  always #2.0345 clk = ~clk; // ~245.76 MHz

  logic        rst_n;
  logic [7:0]  awaddr, araddr;
  logic        awvalid, awready, wvalid, wready, bvalid, bready;
  logic [31:0] wdata, rdata;
  logic [3:0]  wstrb;
  logic [1:0]  bresp, rresp;
  logic        arvalid, arready, rvalid, rready;

  logic signed [15:0] s_tdata, m_tdata;
  logic               s_tvalid, s_tready, s_tlast;
  logic               m_tvalid, m_tready, m_tlast;

  {block} dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axil_awaddr  (awaddr),
    .s_axil_awvalid (awvalid),
    .s_axil_awready (awready),
    .s_axil_wdata   (wdata),
    .s_axil_wstrb   (wstrb),
    .s_axil_wvalid  (wvalid),
    .s_axil_wready  (wready),
    .s_axil_bresp   (bresp),
    .s_axil_bvalid  (bvalid),
    .s_axil_bready  (bready),
    .s_axil_araddr  (araddr),
    .s_axil_arvalid (arvalid),
    .s_axil_arready (arready),
    .s_axil_rdata   (rdata),
    .s_axil_rresp   (rresp),
    .s_axil_rvalid  (rvalid),
    .s_axil_rready  (rready),
    .s_axis_tdata   (s_tdata),
    .s_axis_tvalid  (s_tvalid),
    .s_axis_tready  (s_tready),
    .s_axis_tlast   (s_tlast),
    .m_axis_tdata   (m_tdata),
    .m_axis_tvalid  (m_tvalid),
    .m_axis_tready  (m_tready),
    .m_axis_tlast   (m_tlast)
  );

  logic [15:0] stim_mem [0:N-1];
  logic [15:0] exp_mem  [0:N-1];
  int errs = 0;

  task automatic axil_read(input logic [7:0] addr, output logic [31:0] val);
    @(posedge clk);
    araddr  <= addr;
    arvalid <= 1'b1;
    rready  <= 1'b1;
    do @(posedge clk); while (!arready);
    arvalid <= 1'b0;
    do @(posedge clk); while (!rvalid);
    val = rdata;
    rready <= 1'b0;
  endtask

  initial begin
    string vec_dir;
    logic [31:0] ver;
    int tx_idx, rx_idx;

    if (!$value$plusargs("VEC_DIR=%s", vec_dir)) vec_dir = "test_vectors";
    $readmemh({{vec_dir, "/{block}_stim.mem"}}, stim_mem);
    $readmemh({{vec_dir, "/{block}_exp.mem"}}, exp_mem);

    rst_n    = 1'b0;
    awaddr   = '0; awvalid = 1'b0; wdata = '0; wstrb = 4'hF; wvalid = 1'b0; bready = 1'b0;
    araddr   = '0; arvalid = 1'b0; rready = 1'b0;
    s_tdata  = '0; s_tvalid = 1'b0; s_tlast = 1'b0; m_tready = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    axil_read(8'h00, ver);
    if (ver !== 32'h{magic_hex}) begin
      $display("ERROR: VERSION=0x%08X expected 0x{magic_hex}", ver);
      errs++;
    end

    tx_idx = 0;
    rx_idx = 0;
    while (rx_idx < N) begin
      @(posedge clk);
      m_tready <= ($urandom_range(0, 3) != 0);
      if (s_tvalid && s_tready) tx_idx++;
      if (tx_idx < N && (!s_tvalid || s_tready)) begin
        s_tvalid <= ($urandom_range(0, 3) != 0);
        s_tdata  <= signed'(stim_mem[tx_idx]);
        s_tlast  <= (tx_idx == N - 1);
      end else if (s_tvalid && s_tready) begin
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
      end
      if (m_tvalid && m_tready) begin
        if (m_tdata !== signed'(exp_mem[rx_idx])) begin
          $display("ERROR sample %0d: got %0d exp %0d", rx_idx, m_tdata, signed'(exp_mem[rx_idx]));
          errs++;
        end
        rx_idx++;
      end
    end

    if (errs == 0) begin
      $display("ALL TESTS PASSED (0 ERRORS) [{block}]");
      $finish;
    end else begin
      $fatal(1, "FAIL [{block}]: %0d ERRORS", errs);
    end
  end
endmodule
'''


BAT_TEMPLATE = '''@echo off
setlocal
pushd "%~dp0"
if "%VIVADO_BIN%"=="" set "VIVADO_BIN=C:\\AMDDesignTools\\2026.1\\Vivado\\bin"

if exist xsim.dir\\tb_{block}_snap rmdir /s /q xsim.dir\\tb_{block}_snap
del /q xvlog.* xelab.* xsim.* *.wdb *.jou 2>nul

call "%VIVADO_BIN%\\xvlog.bat" -sv ..\\rtl\\{block}.sv ..\\tb\\tb_{block}.sv
if %ERRORLEVEL% neq 0 (set "RC=1" & goto :cleanup)

call "%VIVADO_BIN%\\xelab.bat" -debug typical -top tb_{block} -snapshot tb_{block}_snap
if %ERRORLEVEL% neq 0 (set "RC=1" & goto :cleanup)
if not exist xsim.dir\\tb_{block}_snap\\xsimk.exe (
  echo ERROR: snapshot executable xsimk.exe missing!
  set "RC=1" & goto :cleanup
)

call "%VIVADO_BIN%\\xsim.bat" tb_{block}_snap -runall -testplusarg "VEC_DIR=../test_vectors"
set "RC=%ERRORLEVEL%"

:cleanup
if exist xsim.dir rmdir /s /q xsim.dir
del /q xvlog.* xelab.* xsim.* *.wdb *.jou 2>nul
popd
exit /b %RC%
'''


SH_TEMPLATE = '''#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
cd "$SCRIPT_DIR"
cleanup() {{
  rm -rf xsim.dir xvlog.* xelab.* xsim.* *.wdb *.jou
}}
trap cleanup EXIT
cleanup

VIVADO_BIN="${{VIVADO_BIN:-$(dirname "$(command -v vivado)")}}"
"$VIVADO_BIN/xvlog" -sv ../rtl/{block}.sv ../tb/tb_{block}.sv
"$VIVADO_BIN/xelab" -debug typical -top tb_{block} -snapshot tb_{block}_snap
"$VIVADO_BIN/xsim" tb_{block}_snap -runall -testplusarg VEC_DIR=../test_vectors
'''


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Scaffold a DSP block across Stage 1 -> 2A -> 2C (run after Stage 0 SPEC.md approval)."
    )
    parser.add_argument("--block", required=True, help="Snake_case block name (e.g. my_filter)")
    parser.add_argument("--repo", default=".", help="Target repository root path")
    parser.add_argument("--magic", default=None, help="4-char ASCII VERSION ID (default: first 4 chars upper)")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    args = parser.parse_args()

    block = args.block.strip()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", block):
        print(f"ERROR: --block '{block}' must match [a-z][a-z0-9_]*", file=sys.stderr)
        return 1

    raw_magic = args.magic if args.magic is not None else (block.replace("_", "").upper() + "1234")[:4]
    if len(raw_magic) != 4 or not all(32 <= ord(c) < 127 for c in raw_magic):
        print("ERROR: --magic must be exactly 4 printable ASCII characters", file=sys.stderr)
        return 1
    magic_hex = "".join(f"{ord(c):02X}" for c in raw_magic)

    repo = Path(args.repo).resolve()
    targets: dict[Path, str] = {
        repo / "python" / f"{block}_golden.py": GOLDEN_TEMPLATE.format(block=block),
        repo / "python" / f"generate_{block}_vectors.py": VECTORS_TEMPLATE.format(block=block),
        repo / "rtl" / f"{block}.sv": RTL_TEMPLATE.format(block=block, magic=raw_magic, magic_hex=magic_hex),
        repo / "tb" / f"tb_{block}.sv": TB_TEMPLATE.format(block=block, magic_hex=magic_hex),
        repo / "sim" / f"run_sim_{block}.bat": BAT_TEMPLATE.format(block=block),
        repo / "sim" / f"run_sim_{block}.sh": SH_TEMPLATE.format(block=block),
    }

    if not args.force:
        conflicts = [p for p in targets if p.exists()]
        if conflicts:
            for p in conflicts:
                print(f"ERROR: file already exists (pass --force to overwrite): {p}", file=sys.stderr)
            return 1

    for path, content in targets.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        print(f"CREATED {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
