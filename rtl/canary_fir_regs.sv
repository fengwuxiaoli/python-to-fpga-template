// ==============================================================================
// AXI4-Lite Register Bank for Canary 15-Tap Symmetric FIR
// Address Map (8-bit byte offset):
//   0x00 (RO)    : VERSION = 32'h46495231 ("FIR1") — Phase 1 JTAG/PS liveness check
//   0x04 (RW)    : CTRL    ([0] = bypass_en)
//   0x08 (R/W1C) : STATUS  ([0] = ovf_sticky, write 1 to clear)
//   0x10..0x2C   : COEFF[0..7] (signed 16-bit Q1.15 symmetric taps, wdata[15:0])
// ==============================================================================
`timescale 1ns / 1ps

module canary_fir_regs #(
  parameter logic [31:0] VERSION_ID = 32'h46495231 // "FIR1"
)(
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite Slave Interface
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

  // Hardware Control & Telemetry
  input  logic               ovf_pulse_i,
  output logic               bypass_en_o,
  output logic               ovf_sticky_o,
  output logic signed [15:0] coeff_o [0:7]
);

  localparam logic signed [15:0] DEFAULT_COEFFS [0:7] = '{
    -16'sd214,
    -16'sd327,
     16'sd0,
     16'sd992,
     16'sd2525,
     16'sd4351,
     16'sd5839,
     16'sd6435
  };

  logic        aw_seen_q, w_seen_q;
  logic [7:0]  aw_addr_q;
  logic [31:0] w_data_q;
  logic [3:0]  w_strb_q;

  logic               bypass_en_q;
  logic               ovf_sticky_q;
  logic signed [15:0] coeff_q [0:7];

  assign bypass_en_o  = bypass_en_q;
  assign ovf_sticky_o = ovf_sticky_q;
  for (genvar k = 0; k < 8; k++) begin : gen_coeff_out
    assign coeff_o[k] = coeff_q[k];
  end

  assign s_axil_awready = !aw_seen_q && !s_axil_bvalid;
  assign s_axil_wready  = !w_seen_q  && !s_axil_bvalid;
  assign s_axil_bresp   = 2'b00;
  assign s_axil_arready = !s_axil_rvalid;
  assign s_axil_rresp   = 2'b00;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_seen_q     <= 1'b0;
      w_seen_q      <= 1'b0;
      aw_addr_q     <= 8'd0;
      w_data_q      <= 32'd0;
      w_strb_q      <= 4'd0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata  <= 32'd0;
      bypass_en_q   <= 1'b0;
      ovf_sticky_q  <= 1'b0;
      for (int i = 0; i < 8; i++) begin
        coeff_q[i] <= DEFAULT_COEFFS[i];
      end
    end else begin
      // Sticky overflow latch (software clears via W1C below)
      if (ovf_pulse_i) begin
        ovf_sticky_q <= 1'b1;
      end

      // Write address/data capture
      if (s_axil_awvalid && s_axil_awready) begin
        aw_seen_q <= 1'b1;
        aw_addr_q <= s_axil_awaddr;
      end
      if (s_axil_wvalid && s_axil_wready) begin
        w_seen_q <= 1'b1;
        w_data_q <= s_axil_wdata;
        w_strb_q <= s_axil_wstrb;
      end

      if ((aw_seen_q || (s_axil_awvalid && s_axil_awready)) &&
          (w_seen_q  || (s_axil_wvalid  && s_axil_wready))  && !s_axil_bvalid) begin
        automatic logic [7:0]  wr_addr = aw_seen_q ? aw_addr_q : s_axil_awaddr;
        automatic logic [31:0] wr_data = w_seen_q  ? w_data_q  : s_axil_wdata;
        automatic logic [3:0]  wr_strb = w_seen_q  ? w_strb_q  : s_axil_wstrb;

        case (wr_addr)
          8'h04: begin
            if (wr_strb[0]) bypass_en_q <= wr_data[0];
          end
          8'h08: begin
            if (wr_strb[0] && wr_data[0]) ovf_sticky_q <= ovf_pulse_i;
          end
          8'h10, 8'h14, 8'h18, 8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C: begin
            if (wr_strb[1:0] == 2'b11) begin
              coeff_q[(wr_addr - 8'h10) >> 2] <= signed'(wr_data[15:0]);
            end
          end
          default: ;
        endcase

        aw_seen_q     <= 1'b0;
        w_seen_q      <= 1'b0;
        s_axil_bvalid <= 1'b1;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      // Read channel
      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_rvalid <= 1'b1;
        case (s_axil_araddr)
          8'h00: s_axil_rdata <= VERSION_ID;
          8'h04: s_axil_rdata <= {31'd0, bypass_en_q};
          8'h08: s_axil_rdata <= {31'd0, ovf_sticky_q};
          8'h10, 8'h14, 8'h18, 8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C: begin
            automatic logic [2:0] idx = 3'((s_axil_araddr - 8'h10) >> 2);
            s_axil_rdata <= {{16{coeff_q[idx][15]}}, coeff_q[idx]};
          end
          default: s_axil_rdata <= 32'd0;
        endcase
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

endmodule
