// ==============================================================================
// Top-Level SystemVerilog Integration for Canary 15-Tap Symmetric FIR
// ==============================================================================
`timescale 1ns / 1ps

module canary_fir_top #(
  parameter logic [31:0] VERSION_ID = 32'h46495231 // "FIR1"
)(
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite Control Plane
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

  // AXI4-Stream Data Plane (Q1.15)
  input  logic signed [15:0] s_axis_tdata,
  input  logic               s_axis_tvalid,
  output logic               s_axis_tready,
  input  logic               s_axis_tlast,

  output logic signed [15:0] m_axis_tdata,
  output logic               m_axis_tvalid,
  input  logic               m_axis_tready,
  output logic               m_axis_tlast,

  // Sticky overflow indicator (LED / GPIO)
  output logic               ovf_sticky_o
);

  logic               bypass_en;
  logic               ovf_pulse;
  logic signed [15:0] coeffs [0:7];

  canary_fir_regs #(
    .VERSION_ID (VERSION_ID)
  ) u_regs (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axil_awaddr  (s_axil_awaddr),
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awready (s_axil_awready),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wstrb   (s_axil_wstrb),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bready  (s_axil_bready),
    .s_axil_araddr  (s_axil_araddr),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_arready (s_axil_arready),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rready  (s_axil_rready),
    .ovf_pulse_i    (ovf_pulse),
    .bypass_en_o    (bypass_en),
    .ovf_sticky_o   (ovf_sticky_o),
    .coeff_o        (coeffs)
  );

  canary_fir_core u_core (
    .clk           (clk),
    .rst_n         (rst_n),
    .bypass_en_i   (bypass_en),
    .coeff_i       (coeffs),
    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .s_axis_tlast  (s_axis_tlast),
    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tlast  (m_axis_tlast),
    .ovf_pulse_o   (ovf_pulse)
  );

endmodule
