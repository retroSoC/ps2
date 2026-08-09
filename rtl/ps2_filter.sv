// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ps2_filter (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [1:0] async_i,
    input  logic [3:0] stable_cycles_i,
    output logic [1:0] filtered_o,
    output logic       ps2_clk_fall_o
    // verilog_format: on
);

  logic [1:0] s_sync;
  logic [1:0] s_filtered_d, s_filtered_q;
  logic [3:0] s_count_d[0:1];
  logic [3:0] s_count_q[0:1];

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_line_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (async_i),
      .dat_o  (s_sync)
  );

  always_comb begin
    s_filtered_d = s_filtered_q;
    for (int line_idx = 0; line_idx < 2; line_idx++) begin
      s_count_d[line_idx] = s_count_q[line_idx];
      if (s_sync[line_idx] == s_filtered_q[line_idx]) begin
        s_count_d[line_idx] = '0;
      end else if (s_count_q[line_idx] + 1'b1 >= stable_cycles_i) begin
        s_filtered_d[line_idx] = s_sync[line_idx];
        s_count_d[line_idx]    = '0;
      end else begin
        s_count_d[line_idx] = s_count_q[line_idx] + 1'b1;
      end
    end
  end

  dffer #(
      .DATA_WIDTH(2)
  ) u_filtered_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_filtered_d),
      .dat_o  (s_filtered_q)
  );

  for (genvar line_idx = 0; line_idx < 2; line_idx++) begin : gen_filter_count
    dffer #(
        .DATA_WIDTH(4)
    ) u_count_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (1'b1),
        .dat_i  (s_count_d[line_idx]),
        .dat_o  (s_count_q[line_idx])
    );
  end

  assign filtered_o     = s_filtered_q;
  assign ps2_clk_fall_o = s_filtered_q[0] && !s_filtered_d[0];

endmodule
