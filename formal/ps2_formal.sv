// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ps2_formal_props #(
    parameter int RX_FIFO_DEPTH = 4,
    parameter int TX_FIFO_DEPTH = 4
) (
    // verilog_format: off
    input logic       clk_i,
    input logic       rst_n_i,
    input logic       enable_i,
    input logic [7:0] rx_level_i,
    input logic [7:0] tx_level_i,
    input logic       ps2_clk_o_i,
    input logic       ps2_dat_o_i,
    input logic       ps2_clk_oe_i,
    input logic       ps2_dat_oe_i,
    input logic       irq_i,
    input logic [5:0] intr_state_i,
    input logic [5:0] intr_enable_i
    // verilog_format: on
);

  always @(posedge clk_i) begin
    assert (rx_level_i <= RX_FIFO_DEPTH);
    assert (tx_level_i <= TX_FIFO_DEPTH);
    assert (!ps2_clk_o_i);
    assert (!ps2_dat_o_i);
    assert (irq_i == |(intr_state_i & intr_enable_i));
    if (!enable_i) begin
      assert (!ps2_clk_oe_i);
      assert (!ps2_dat_oe_i);
    end
  end

endmodule

module ps2_formal;

  (* gclk *)logic        clk;
  (* anyseq *)logic        rst_n;
  (* anyseq *)logic [11:0] paddr;
  (* anyseq *)logic        psel;
  (* anyseq *)logic        penable;
  (* anyseq *)logic        pwrite;
  (* anyseq *)logic [31:0] pwdata;
  (* anyseq *)logic [ 3:0] pstrb;
  (* anyseq *)logic        ps2_clk;
  (* anyseq *)logic        ps2_dat;

  logic        pready;
  logic [31:0] prdata;
  logic        pslverr;
  logic        ps2_clk_o;
  logic        ps2_clk_oe;
  logic        ps2_dat_o;
  logic        ps2_dat_oe;
  logic        irq;
  logic        f_past_valid;

  ps2_reg #(
      .PCLK_HZ      (1_000_000),
      .RX_FIFO_DEPTH(4),
      .TX_FIFO_DEPTH(4)
  ) u_dut (
      .clk_i       (clk),
      .rst_n_i     (rst_n),
      .paddr_i     (paddr),
      .psel_i      (psel),
      .penable_i   (penable),
      .pwrite_i    (pwrite),
      .pwdata_i    (pwdata),
      .pstrb_i     (pstrb),
      .pready_o    (pready),
      .prdata_o    (prdata),
      .pslverr_o   (pslverr),
      .ps2_clk_i   (ps2_clk),
      .ps2_clk_o   (ps2_clk_o),
      .ps2_clk_oe_o(ps2_clk_oe),
      .ps2_dat_i   (ps2_dat),
      .ps2_dat_o   (ps2_dat_o),
      .ps2_dat_oe_o(ps2_dat_oe),
      .irq_o       (irq)
  );

  initial begin
    f_past_valid = 1'b0;
    assume (!rst_n);
  end

  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    assert (pready);
    assert (!pslverr || (psel && penable));
    if (!rst_n) begin
      assert (!irq);
      assert (!ps2_clk_oe);
      assert (!ps2_dat_oe);
    end
    cover (f_past_valid && rst_n && pslverr);
    cover (f_past_valid && rst_n && ps2_clk_oe);
    cover (f_past_valid && rst_n && irq);
  end

endmodule
