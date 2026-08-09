// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ps2_rx (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic        tx_active_i,
    input  logic        ps2_clk_fall_i,
    input  logic        ps2_dat_i,
    input  logic [23:0] timeout_cycles_i,
    output logic        active_o,
    output logic        frame_event_o,
    output logic [ 7:0] frame_data_o,
    output logic [ 2:0] frame_error_o,
    output logic        timeout_event_o
    // verilog_format: on
);

  logic [3:0] s_bit_count_d, s_bit_count_q;
  logic [9:0] s_shift_d, s_shift_q;
  logic [23:0] s_timeout_d, s_timeout_q;
  logic s_frame_complete;

  assign active_o = s_bit_count_q != '0;
  assign s_frame_complete = enable_i && !tx_active_i && ps2_clk_fall_i && (s_bit_count_q == 4'd10);
  assign frame_event_o = s_frame_complete;
  assign frame_data_o = s_shift_q[8:1];
  assign frame_error_o[0] = s_shift_q[0];
  assign frame_error_o[1] = !(^s_shift_q[9:1]);
  assign frame_error_o[2] = !ps2_dat_i;
  assign timeout_event_o  = enable_i && !tx_active_i && active_o &&
                            (s_timeout_q + 1'b1 >= timeout_cycles_i) && !ps2_clk_fall_i;

  always_comb begin
    s_bit_count_d = s_bit_count_q;
    s_shift_d     = s_shift_q;
    s_timeout_d   = s_timeout_q;

    if (!enable_i || tx_active_i || timeout_event_o) begin
      s_bit_count_d = '0;
      s_shift_d     = '0;
      s_timeout_d   = '0;
    end else if (ps2_clk_fall_i) begin
      s_timeout_d = '0;
      if (s_bit_count_q == 4'd10) begin
        s_bit_count_d = '0;
      end else begin
        s_shift_d[s_bit_count_q] = ps2_dat_i;
        s_bit_count_d            = s_bit_count_q + 1'b1;
      end
    end else if (active_o) begin
      s_timeout_d = s_timeout_q + 1'b1;
    end
  end

  dffer #(
      .DATA_WIDTH(4)
  ) u_bit_count_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_bit_count_d),
      .dat_o  (s_bit_count_q)
  );

  dffer #(
      .DATA_WIDTH(10)
  ) u_shift_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_shift_d),
      .dat_o  (s_shift_q)
  );

  dffer #(
      .DATA_WIDTH(24)
  ) u_timeout_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );

endmodule
