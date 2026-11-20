// ==============================================================================
// Stage 2C Self-Checking Unit Testbench for Canary 15-Tap Symmetric FIR
// Verifies:
//   1. AXI4-Lite VERSION (0x46495231 "FIR1"), reset CTRL, and default COEFF[7]
//   2. Default coefficients with random tvalid bubbles & tready backpressure
//   3. Delay-line flush (14 zeros) + runtime custom COEFF[0..7] via AXI4-Lite
//   4. Bypass mode (CTRL[0] = 1) with bubbles & backpressure
// ==============================================================================
`timescale 1ns / 1ps

module tb_canary_fir;
  localparam int N_SAMPLES = 256;
  localparam int N_BYPASS  = 32;
  localparam logic [31:0] EXP_VERSION = 32'h46495231; // "FIR1"

  logic clk = 1'b0;
  always #2.0345 clk = ~clk; // 245.76 MHz

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
  logic               ovf_sticky;

  canary_fir_top dut (
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
    .m_axis_tlast   (m_tlast),
    .ovf_sticky_o   (ovf_sticky)
  );

  logic [15:0] stim_mem       [0:N_SAMPLES-1];
  logic [15:0] exp_def_mem    [0:N_SAMPLES-1];
  logic [15:0] exp_cust_mem   [0:N_SAMPLES-1];
  logic [15:0] custom_coeffs  [0:7];

  int total_errs = 0;

  task automatic axil_write(input logic [7:0] addr, input logic [31:0] data);
    bit aw_done = 1'b0;
    bit w_done  = 1'b0;
    int wd      = 0;

    @(posedge clk);
    awaddr  <= addr;
    awvalid <= 1'b1;
    wdata   <= data;
    wstrb   <= 4'hF;
    wvalid  <= 1'b1;
    bready  <= 1'b1;

    while (!aw_done || !w_done) begin
      @(posedge clk);
      if (awvalid && awready) begin
        aw_done = 1'b1;
        awvalid <= 1'b0;
      end
      if (wvalid && wready) begin
        w_done = 1'b1;
        wvalid <= 1'b0;
      end
      wd++;
      if (wd > 200) $fatal(1, "Timeout waiting for AXI4-Lite AW/W handshake at addr 0x%02X", addr);
    end

    wd = 0;
    while (!bvalid) begin
      @(posedge clk);
      wd++;
      if (wd > 200) $fatal(1, "Timeout waiting for AXI4-Lite BVALID at addr 0x%02X", addr);
    end
    if (bresp !== 2'b00) begin
      $display("ERROR: AXI4-Lite write BRESP=%0b at 0x%02X", bresp, addr);
      total_errs++;
    end
    @(posedge clk);
    bready <= 1'b0;
  endtask

  task automatic axil_read(input logic [7:0] addr, output logic [31:0] data);
    int wd = 0;
    @(posedge clk);
    araddr  <= addr;
    arvalid <= 1'b1;
    rready  <= 1'b1;

    do begin
      @(posedge clk);
      wd++;
      if (wd > 200) $fatal(1, "Timeout waiting for AXI4-Lite ARREADY at addr 0x%02X", addr);
    end while (!arready);
    arvalid <= 1'b0;

    wd = 0;
    while (!rvalid) begin
      @(posedge clk);
      wd++;
      if (wd > 200) $fatal(1, "Timeout waiting for AXI4-Lite RVALID at addr 0x%02X", addr);
    end
    data = rdata;
    if (rresp !== 2'b00) begin
      $display("ERROR: AXI4-Lite read RRESP=%0b at 0x%02X", rresp, addr);
      total_errs++;
    end
    @(posedge clk);
    rready <= 1'b0;
  endtask

  task automatic flush_delay_line();
    int tx_cnt = 0;
    int rx_cnt = 0;
    int wd     = 0;

    while (rx_cnt < 14) begin
      @(posedge clk);
      if (s_tvalid && s_tready) tx_cnt++;
      if (m_tvalid && m_tready) rx_cnt++;

      m_tready <= 1'b1;
      if (tx_cnt < 14 && (!s_tvalid || s_tready)) begin
        s_tvalid <= 1'b1;
        s_tdata  <= 16'sd0;
        s_tlast  <= 1'b0;
      end else if (s_tvalid && s_tready) begin
        s_tvalid <= 1'b0;
      end

      wd++;
      if (wd > 500) $fatal(1, "Timeout in flush_delay_line()");
    end
    @(posedge clk);
    s_tvalid <= 1'b0;
    s_tlast  <= 1'b0;
    m_tready <= 1'b0;
    repeat (4) @(posedge clk);
  endtask

  task automatic run_stream_scenario(
    input string      label,
    input logic [15:0] exp_arr [0:N_SAMPLES-1],
    input int         count,
    input bit         use_bubbles,
    input bit         use_backpressure
  );
    int tx_idx    = 0;
    int rx_idx    = 0;
    int wd        = 0;
    int scen_errs = 0;

    while (rx_idx < count) begin
      @(posedge clk);
      if (s_tvalid && s_tready) tx_idx++;

      if (m_tvalid && m_tready) begin
        logic signed [15:0] exp_val = signed'(exp_arr[rx_idx]);
        bit                 exp_last = (rx_idx == (count - 1));
        if (m_tdata !== exp_val || m_tlast !== exp_last) begin
          if (scen_errs < 10) begin
            $display("ERROR [%s] idx=%0d: got data=%0d last=%0b, exp data=%0d last=%0b",
                     label, rx_idx, m_tdata, m_tlast, exp_val, exp_last);
          end
          scen_errs++;
        end
        rx_idx++;
      end

      m_tready <= use_backpressure ? ($urandom_range(0, 3) != 0) : 1'b1;

      if (!s_tvalid || s_tready) begin
        if (tx_idx < count) begin
          if (!use_bubbles || ($urandom_range(0, 3) != 0)) begin
            s_tvalid <= 1'b1;
            s_tdata  <= signed'(stim_mem[tx_idx]);
            s_tlast  <= (tx_idx == (count - 1));
          end else begin
            s_tvalid <= 1'b0;
            s_tlast  <= 1'b0;
          end
        end else begin
          s_tvalid <= 1'b0;
          s_tlast  <= 1'b0;
        end
      end

      wd++;
      if (wd > (count * 20)) $fatal(1, "Timeout in scenario [%s] (rx_idx=%0d/%0d)", label, rx_idx, count);
    end

    @(posedge clk);
    s_tvalid <= 1'b0;
    s_tlast  <= 1'b0;
    m_tready <= 1'b0;

    $display("[TB] Scenario %-28s | samples=%0d | mismatches=%0d", label, count, scen_errs);
    total_errs += scen_errs;
  endtask

  initial begin
    string       vec_dir;
    logic [31:0] rd_val;

    if (!$value$plusargs("VEC_DIR=%s", vec_dir)) vec_dir = "test_vectors";
    $readmemh({vec_dir, "/canary_stim.mem"}, stim_mem);
    $readmemh({vec_dir, "/canary_exp_default.mem"}, exp_def_mem);
    $readmemh({vec_dir, "/canary_exp_custom.mem"}, exp_cust_mem);
    $readmemh({vec_dir, "/canary_coeffs_custom.mem"}, custom_coeffs);

    rst_n    = 1'b0;
    awaddr   = '0; awvalid = 1'b0; wdata = '0; wstrb = 4'h0; wvalid = 1'b0; bready = 1'b0;
    araddr   = '0; arvalid = 1'b0; rready = 1'b0;
    s_tdata  = '0; s_tvalid = 1'b0; s_tlast = 1'b0; m_tready = 1'b0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // Test 1: AXI4-Lite VERSION & Reset Defaults
    axil_read(8'h00, rd_val);
    if (rd_val !== EXP_VERSION) begin
      $display("ERROR: VERSION=0x%08X expected 0x%08X", rd_val, EXP_VERSION);
      total_errs++;
    end else begin
      $display("[TB] AXI4-Lite VERSION readback = 0x%08X (\"FIR1\") PASS", rd_val);
    end

    axil_read(8'h04, rd_val);
    if (rd_val !== 32'd0) begin
      $display("ERROR: reset CTRL=0x%08X expected 0", rd_val);
      total_errs++;
    end

    axil_read(8'h2C, rd_val);
    if (signed'(rd_val) !== 32'sd6435) begin
      $display("ERROR: reset COEFF[7]=%0d expected 6435", signed'(rd_val));
      total_errs++;
    end

    // Test 2: Default coefficients under bubbles + backpressure
    run_stream_scenario("default_bubbles_bp", exp_def_mem, N_SAMPLES, 1'b1, 1'b1);

    // Test 3: Flush SRL delay line + write custom coefficients via AXI4-Lite
    flush_delay_line();
    for (int k = 0; k < 8; k++) begin
      automatic logic [31:0] wr32 = {{16{custom_coeffs[k][15]}}, custom_coeffs[k]};
      axil_write(8'h10 + 8'(k * 4), wr32);
      axil_read(8'h10 + 8'(k * 4), rd_val);
      if (rd_val !== wr32) begin
        $display("ERROR: COEFF[%0d] readback=0x%08X expected 0x%08X", k, rd_val, wr32);
        total_errs++;
      end
    end
    run_stream_scenario("custom_axil_bubbles_bp", exp_cust_mem, N_SAMPLES, 1'b1, 1'b1);

    // Test 4: Bypass mode (CTRL[0] = 1)
    flush_delay_line();
    axil_write(8'h04, 32'h00000001);
    run_stream_scenario("bypass_bubbles_bp", stim_mem, N_BYPASS, 1'b1, 1'b1);

    // Verify zero unexpected overflow sticky flag
    axil_read(8'h08, rd_val);
    if (rd_val[0] !== 1'b0 || ovf_sticky !== 1'b0) begin
      $display("ERROR: Unexpected overflow sticky STATUS=0x%08X", rd_val);
      total_errs++;
    end

    if (total_errs == 0) begin
      $display("ALL TESTS PASSED (0 ERRORS)");
      $finish;
    end else begin
      $fatal(1, "FAIL: %0d ERRORS", total_errs);
    end
  end

endmodule
