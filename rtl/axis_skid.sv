// ==============================================================================
// Two-Entry Registered AXI4-Stream Skid Buffer
// Breaks both forward (tvalid/tdata/tlast) and backward (tready) timing paths
// across subsystem and CDC boundaries without bubbles at full throughput.
// ==============================================================================
`timescale 1ns / 1ps

module axis_skid #(
  parameter int DATA_WIDTH = 16
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic                  s_axis_tlast,

  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic                  m_axis_tlast
);

  logic                  m_valid_q;
  logic [DATA_WIDTH-1:0] m_data_q;
  logic                  m_last_q;

  logic                  skid_valid_q;
  logic [DATA_WIDTH-1:0] skid_data_q;
  logic                  skid_last_q;

  logic                  s_ready_q;

  assign s_axis_tready = s_ready_q;
  assign m_axis_tvalid = m_valid_q;
  assign m_axis_tdata  = m_data_q;
  assign m_axis_tlast  = m_last_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m_valid_q    <= 1'b0;
      m_data_q     <= '0;
      m_last_q     <= 1'b0;
      skid_valid_q <= 1'b0;
      skid_data_q  <= '0;
      skid_last_q  <= 1'b0;
      s_ready_q    <= 1'b1;
    end else begin
      automatic logic in_xfer  = s_axis_tvalid && s_ready_q;
      automatic logic out_xfer = m_valid_q && m_axis_tready;

      if (!m_valid_q) begin
        // Buffer empty
        if (in_xfer) begin
          m_valid_q <= 1'b1;
          m_data_q  <= s_axis_tdata;
          m_last_q  <= s_axis_tlast;
        end
        skid_valid_q <= 1'b0;
        s_ready_q    <= 1'b1;
      end else if (!skid_valid_q) begin
        // Only primary output register occupied
        if (out_xfer && in_xfer) begin
          m_valid_q    <= 1'b1;
          m_data_q     <= s_axis_tdata;
          m_last_q     <= s_axis_tlast;
          skid_valid_q <= 1'b0;
          s_ready_q    <= 1'b1;
        end else if (out_xfer && !in_xfer) begin
          m_valid_q    <= 1'b0;
          skid_valid_q <= 1'b0;
          s_ready_q    <= 1'b1;
        end else if (!out_xfer && in_xfer) begin
          skid_valid_q <= 1'b1;
          skid_data_q  <= s_axis_tdata;
          skid_last_q  <= s_axis_tlast;
          s_ready_q    <= 1'b0;
        end
      end else begin
        // Both primary and skid occupied -> s_ready_q is already 0, in_xfer == 0
        if (out_xfer) begin
          m_valid_q    <= 1'b1;
          m_data_q     <= skid_data_q;
          m_last_q     <= skid_last_q;
          skid_valid_q <= 1'b0;
          s_ready_q    <= 1'b1;
        end else begin
          s_ready_q    <= 1'b0;
        end
      end
    end
  end

endmodule
