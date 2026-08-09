// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ps2_core #(
    parameter int RX_FIFO_DEPTH = 16,
    parameter int TX_FIFO_DEPTH = 16
) (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic        soft_reset_i,
    input  logic        abort_tx_i,
    input  logic        flush_rx_i,
    input  logic        flush_tx_i,
    input  logic [ 3:0] filter_cycles_i,
    input  logic [23:0] inhibit_cycles_i,
    input  logic [23:0] frame_timeout_i,
    input  logic        rx_pop_i,
    output logic [10:0] rx_data_o,
    output logic [ 7:0] rx_level_o,
    output logic        rx_empty_o,
    output logic        rx_full_o,
    input  logic        tx_push_i,
    input  logic [ 7:0] tx_data_i,
    output logic [ 7:0] tx_level_o,
    output logic        tx_empty_o,
    output logic        tx_full_o,
    output logic        rx_active_o,
    output logic        tx_active_o,
    output logic [ 8:0] error_event_o,
    output logic        tx_done_event_o,
    input  logic        ps2_clk_i,
    input  logic        ps2_dat_i,
    output logic        ps2_clk_drive_low_o,
    output logic        ps2_dat_drive_low_o,
    output logic        filtered_clk_o,
    output logic        filtered_dat_o
    // verilog_format: on
);

  localparam int RX_COUNT_WIDTH = $clog2(RX_FIFO_DEPTH) + 1;
  localparam int TX_COUNT_WIDTH = $clog2(TX_FIFO_DEPTH) + 1;

  logic [               1:0] s_filtered_lines;
  logic                      s_ps2_clk_fall;
  logic                      s_rx_frame_event;
  logic [               7:0] s_rx_frame_data;
  logic [               2:0] s_rx_frame_error;
  logic                      s_rx_timeout_event;
  logic                      s_rx_push;
  logic [RX_COUNT_WIDTH-1:0] s_rx_count;
  logic [               7:0] s_tx_fifo_data;
  logic                      s_tx_pop;
  logic [TX_COUNT_WIDTH-1:0] s_tx_count;
  logic                      s_tx_timeout_event;
  logic                      s_tx_no_ack_event;
  logic                      s_tx_aborted_event;
  logic                      s_tx_clk_drive_low;
  logic                      s_tx_dat_drive_low;
  logic [23:0] s_bus_stuck_count_d, s_bus_stuck_count_q;
  logic s_bus_stuck_event;

  initial begin
    if ((RX_FIFO_DEPTH < 2) || (RX_FIFO_DEPTH > 256) ||
        ((RX_FIFO_DEPTH & (RX_FIFO_DEPTH - 1)) != 0)) begin
      $fatal(1, "ps2_core: RX_FIFO_DEPTH must be a power of two from 2 through 256");
    end
    if ((TX_FIFO_DEPTH < 2) || (TX_FIFO_DEPTH > 256) ||
        ((TX_FIFO_DEPTH & (TX_FIFO_DEPTH - 1)) != 0)) begin
      $fatal(1, "ps2_core: TX_FIFO_DEPTH must be a power of two from 2 through 256");
    end
  end

  ps2_filter u_ps2_filter (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .async_i        ({ps2_dat_i, ps2_clk_i}),
      .stable_cycles_i(filter_cycles_i),
      .filtered_o     (s_filtered_lines),
      .ps2_clk_fall_o (s_ps2_clk_fall)
  );

  ps2_rx u_ps2_rx (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .enable_i        (enable_i),
      .tx_active_i     (tx_active_o),
      .ps2_clk_fall_i  (s_ps2_clk_fall),
      .ps2_dat_i       (s_filtered_lines[1]),
      .timeout_cycles_i(frame_timeout_i),
      .active_o        (rx_active_o),
      .frame_event_o   (s_rx_frame_event),
      .frame_data_o    (s_rx_frame_data),
      .frame_error_o   (s_rx_frame_error),
      .timeout_event_o (s_rx_timeout_event)
  );

  assign s_rx_push = s_rx_frame_event && !rx_full_o;
  fifo #(
      .DATA_WIDTH      (11),
      .BUFFER_DEPTH    (RX_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH($clog2(RX_FIFO_DEPTH))
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(!enable_i || soft_reset_i || flush_rx_i),
      .push_i (s_rx_push),
      .full_o (rx_full_o),
      .dat_i  ({s_rx_frame_error, s_rx_frame_data}),
      .pop_i  (rx_pop_i),
      .empty_o(rx_empty_o),
      .dat_o  (rx_data_o),
      .cnt_o  (s_rx_count)
  );

  fifo #(
      .DATA_WIDTH      (8),
      .BUFFER_DEPTH    (TX_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH($clog2(TX_FIFO_DEPTH))
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(!enable_i || soft_reset_i || flush_tx_i || abort_tx_i),
      .push_i (tx_push_i),
      .full_o (tx_full_o),
      .dat_i  (tx_data_i),
      .pop_i  (s_tx_pop),
      .empty_o(tx_empty_o),
      .dat_o  (s_tx_fifo_data),
      .cnt_o  (s_tx_count)
  );

  ps2_tx u_ps2_tx (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .enable_i        (enable_i),
      .abort_i         (abort_tx_i || soft_reset_i),
      .data_valid_i    (!tx_empty_o),
      .data_i          (s_tx_fifo_data),
      .data_pop_o      (s_tx_pop),
      .ps2_clk_i       (s_filtered_lines[0]),
      .ps2_dat_i       (s_filtered_lines[1]),
      .ps2_clk_fall_i  (s_ps2_clk_fall),
      .inhibit_cycles_i(inhibit_cycles_i),
      .timeout_cycles_i(frame_timeout_i),
      .clk_drive_low_o (s_tx_clk_drive_low),
      .dat_drive_low_o (s_tx_dat_drive_low),
      .active_o        (tx_active_o),
      .done_event_o    (tx_done_event_o),
      .timeout_event_o (s_tx_timeout_event),
      .no_ack_event_o  (s_tx_no_ack_event),
      .aborted_event_o (s_tx_aborted_event)
  );

  assign s_bus_stuck_event = enable_i && !rx_active_o && !tx_active_o &&
                             !(s_filtered_lines[0] && s_filtered_lines[1]) &&
                             (s_bus_stuck_count_q + 1'b1 >= frame_timeout_i);

  always_comb begin
    s_bus_stuck_count_d = s_bus_stuck_count_q;
    if (!enable_i || rx_active_o || tx_active_o ||
        (s_filtered_lines[0] && s_filtered_lines[1]) || s_bus_stuck_event) begin
      s_bus_stuck_count_d = '0;
    end else begin
      s_bus_stuck_count_d = s_bus_stuck_count_q + 1'b1;
    end
  end

  dffer #(
      .DATA_WIDTH(24)
  ) u_bus_stuck_count_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_bus_stuck_count_d),
      .dat_o  (s_bus_stuck_count_q)
  );

  assign rx_level_o          = 8'(s_rx_count);
  assign tx_level_o          = 8'(s_tx_count);
  assign filtered_clk_o      = s_filtered_lines[0];
  assign filtered_dat_o      = s_filtered_lines[1];
  assign ps2_clk_drive_low_o = enable_i && s_tx_clk_drive_low;
  assign ps2_dat_drive_low_o = enable_i && s_tx_dat_drive_low;
  assign error_event_o[2:0]  = s_rx_frame_event ? s_rx_frame_error : '0;
  assign error_event_o[3]    = s_rx_timeout_event;
  assign error_event_o[4]    = s_rx_frame_event && rx_full_o;
  assign error_event_o[5]    = s_tx_timeout_event;
  assign error_event_o[6]    = s_tx_no_ack_event;
  assign error_event_o[7]    = s_tx_aborted_event;
  assign error_event_o[8]    = s_bus_stuck_event;

endmodule
