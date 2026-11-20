// ==============================================================================
// 15-Tap Symmetric FIR Core (4-Stage Pipelined, DSP48E2 + Reset-Free SRLs)
// Matches `python/canary_fir_golden.py::fir_fixed` bit-for-bit.
//
// Synthesis lessons embedded directly:
//   L2: Data shift chain `d[0:13]` and DSP data registers are reset-free so
//       Vivado packs SRLs and DSP48E2 AREG/MREG cleanly.
//   L4: Pipeline advances on `pipe_en = !core_tvalid || core_tready` (not
//       gated on `s_axis_tvalid`) so tail samples drain without hanging; output
//       passes through `axis_skid` to break combinational `tready` loops.
// ==============================================================================
`timescale 1ns / 1ps

module canary_fir_core (
  input  logic               clk,
  input  logic               rst_n,

  input  logic               bypass_en_i,
  input  logic signed [15:0] coeff_i [0:7],

  input  logic signed [15:0] s_axis_tdata,
  input  logic               s_axis_tvalid,
  output logic               s_axis_tready,
  input  logic               s_axis_tlast,

  output logic signed [15:0] m_axis_tdata,
  output logic               m_axis_tvalid,
  input  logic               m_axis_tready,
  output logic               m_axis_tlast,

  output logic               ovf_pulse_o
);

  // Downstream skid interface signals
  logic signed [15:0] core_tdata_q;
  logic               core_tvalid_q;
  logic               core_tready;
  logic               core_tlast_q;
  logic               core_ovf_q;

  logic pipe_en;
  assign pipe_en       = !core_tvalid_q || core_tready;
  assign s_axis_tready = pipe_en;

  // Reset-free 14-sample shift register chain (`d[0]` = x[-1], `d[13]` = x[-14])
  logic signed [15:0] d [0:13] = '{default: 16'sd0};

  // Pipeline data registers (reset-free for DSP48E2 & SRL packing)
  logic signed [16:0] p_s1      [0:7] = '{default: 17'sd0};
  logic signed [15:0] bypass_s1       = 16'sd0;

  logic signed [32:0] prod_s2   [0:7] = '{default: 33'sd0};
  logic signed [15:0] bypass_s2       = 16'sd0;

  logic signed [34:0] sum_s3    [0:3] = '{default: 35'sd0};
  logic signed [15:0] bypass_s3       = 16'sd0;

  // Control/valid pipeline (synchronous active-low reset)
  logic v_s1_q, v_s2_q, v_s3_q;
  logic last_s1_q, last_s2_q, last_s3_q;

  // Combinational final sum + round + saturate for Stage 4 (38-bit avoids ASSIGN-1)
  logic signed [37:0] acc_comb;
  logic signed [37:0] acc_rnd_comb;
  logic signed [37:0] scaled_comb;
  logic signed [15:0] sat_comb;
  logic               ovf_comb;

  always_comb begin
    acc_comb = $signed({{3{sum_s3[0][34]}}, sum_s3[0]}) +
               $signed({{3{sum_s3[1][34]}}, sum_s3[1]}) +
               $signed({{3{sum_s3[2][34]}}, sum_s3[2]}) +
               $signed({{3{sum_s3[3][34]}}, sum_s3[3]});
    acc_rnd_comb = acc_comb + 38'sd16384;
    scaled_comb  = acc_rnd_comb >>> 15;

    if (scaled_comb > 38'sd32767) begin
      sat_comb = 16'sd32767;
      ovf_comb = 1'b1;
    end else if (scaled_comb < -38'sd32768) begin
      sat_comb = -16'sd32768;
      ovf_comb = 1'b1;
    end else begin
      sat_comb = scaled_comb[15:0];
      ovf_comb = 1'b0;
    end
  end

  // Delay line shifts strictly on accepted input samples
  always_ff @(posedge clk) begin
    if (s_axis_tvalid && pipe_en) begin
      d[0] <= s_axis_tdata;
      for (int i = 1; i < 14; i++) begin
        d[i] <= d[i - 1];
      end
    end
  end

  // Reset-free datapath stages 1 -> 2 -> 3
  always_ff @(posedge clk) begin
    if (pipe_en) begin
      // Stage 1: Symmetric pre-add
      p_s1[0] <= $signed({s_axis_tdata[15], s_axis_tdata}) + $signed({d[13][15], d[13]});
      for (int k = 1; k < 7; k++) begin
        p_s1[k] <= $signed({d[k - 1][15], d[k - 1]}) + $signed({d[13 - k][15], d[13 - k]});
      end
      p_s1[7]   <= $signed({d[6][15], d[6]});
      bypass_s1 <= s_axis_tdata;

      // Stage 2: Multiply (8x DSP48E2 MREG)
      for (int k = 0; k < 8; k++) begin
        prod_s2[k] <= p_s1[k] * coeff_i[k];
      end
      bypass_s2 <= bypass_s1;

      // Stage 3: Pairwise adder tree level 1
      for (int g = 0; g < 4; g++) begin
        sum_s3[g] <= $signed({{2{prod_s2[2 * g][32]}}, prod_s2[2 * g]}) +
                     $signed({{2{prod_s2[2 * g + 1][32]}}, prod_s2[2 * g + 1]});
      end
      bypass_s3 <= bypass_s2;

      // Stage 4 data output
      core_tdata_q <= bypass_en_i ? bypass_s3 : sat_comb;
    end
  end

  // Valid / last / overflow control registers (synchronous reset)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v_s1_q        <= 1'b0;
      v_s2_q        <= 1'b0;
      v_s3_q        <= 1'b0;
      last_s1_q     <= 1'b0;
      last_s2_q     <= 1'b0;
      last_s3_q     <= 1'b0;
      core_tvalid_q <= 1'b0;
      core_tlast_q  <= 1'b0;
      core_ovf_q    <= 1'b0;
    end else if (pipe_en) begin
      v_s1_q        <= s_axis_tvalid;
      v_s2_q        <= v_s1_q;
      v_s3_q        <= v_s2_q;
      last_s1_q     <= s_axis_tlast;
      last_s2_q     <= last_s1_q;
      last_s3_q     <= last_s2_q;
      core_tvalid_q <= v_s3_q;
      core_tlast_q  <= last_s3_q;
      core_ovf_q    <= v_s3_q && !bypass_en_i && ovf_comb;
    end else begin
      core_ovf_q    <= 1'b0;
    end
  end

  assign ovf_pulse_o = core_ovf_q;

  axis_skid #(
    .DATA_WIDTH (16)
  ) u_out_skid (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axis_tdata  (core_tdata_q),
    .s_axis_tvalid (core_tvalid_q),
    .s_axis_tready (core_tready),
    .s_axis_tlast  (core_tlast_q),
    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tlast  (m_axis_tlast)
  );

endmodule
