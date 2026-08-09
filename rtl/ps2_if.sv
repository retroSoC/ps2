// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

interface ps2_if ();
  logic ps2_clk_i;
  logic ps2_clk_o;
  logic ps2_clk_oe_o;
  logic ps2_dat_i;
  logic ps2_dat_o;
  logic ps2_dat_oe_o;
  logic irq_o;

  modport dut(
      input ps2_clk_i,
      input ps2_dat_i,
      output ps2_clk_o,
      output ps2_clk_oe_o,
      output ps2_dat_o,
      output ps2_dat_oe_o,
      output irq_o
  );

  modport tb(
      output ps2_clk_i,
      output ps2_dat_i,
      input ps2_clk_o,
      input ps2_clk_oe_o,
      input ps2_dat_o,
      input ps2_dat_oe_o,
      input irq_o
  );
endinterface
