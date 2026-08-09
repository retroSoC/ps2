// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apb4_ps2 #(
    parameter int PCLK_HZ       = 72_000_000,
    parameter int RX_FIFO_DEPTH = 16,
    parameter int TX_FIFO_DEPTH = 16
) (
    // verilog_format: off
    apb4_if.slave apb4,
    ps2_if.dut    ps2
    // verilog_format: on
);

  ps2_reg #(
      .PCLK_HZ      (PCLK_HZ),
      .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
      .TX_FIFO_DEPTH(TX_FIFO_DEPTH)
  ) u_ps2_reg (
      .clk_i       (apb4.pclk),
      .rst_n_i     (apb4.presetn),
      .paddr_i     (apb4.paddr[11:0]),
      .psel_i      (apb4.psel),
      .penable_i   (apb4.penable),
      .pwrite_i    (apb4.pwrite),
      .pwdata_i    (apb4.pwdata),
      .pstrb_i     (apb4.pstrb),
      .pready_o    (apb4.pready),
      .prdata_o    (apb4.prdata),
      .pslverr_o   (apb4.pslverr),
      .ps2_clk_i   (ps2.ps2_clk_i),
      .ps2_clk_o   (ps2.ps2_clk_o),
      .ps2_clk_oe_o(ps2.ps2_clk_oe_o),
      .ps2_dat_i   (ps2.ps2_dat_i),
      .ps2_dat_o   (ps2.ps2_dat_o),
      .ps2_dat_oe_o(ps2.ps2_dat_oe_o),
      .irq_o       (ps2.irq_o)
  );

`ifndef SV_ASSRT_DISABLE
  xchecker #(
      .DATA_WIDTH(2)
  ) u_line_xchecker (
      .clk_i(apb4.pclk),
      .dat_i({ps2.ps2_clk_i, ps2.ps2_dat_i})
  );
`endif

endmodule
