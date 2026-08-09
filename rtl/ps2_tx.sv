// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ps2_tx (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic        abort_i,
    input  logic        data_valid_i,
    input  logic [ 7:0] data_i,
    output logic        data_pop_o,
    input  logic        ps2_clk_i,
    input  logic        ps2_dat_i,
    input  logic        ps2_clk_fall_i,
    input  logic [23:0] inhibit_cycles_i,
    input  logic [23:0] timeout_cycles_i,
    output logic        clk_drive_low_o,
    output logic        dat_drive_low_o,
    output logic        active_o,
    output logic        done_event_o,
    output logic        timeout_event_o,
    output logic        no_ack_event_o,
    output logic        aborted_event_o
    // verilog_format: on
);

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_INHIBIT,
    ST_REQUEST,
    ST_SHIFT,
    ST_PARITY,
    ST_STOP,
    ST_WAIT_IDLE
  } state_t;

  state_t s_state_d, s_state_q;
  logic [7:0] s_data_d, s_data_q;
  logic [3:0] s_bit_index_d, s_bit_index_q;
  logic [2:0] s_data_index;
  logic [23:0] s_timer_d, s_timer_q;
  logic s_parity;
  logic s_waiting_for_clock;

  assign active_o = s_state_q != ST_IDLE;
  assign data_pop_o = enable_i && (s_state_q == ST_IDLE) && data_valid_i && ps2_clk_i && ps2_dat_i;
  assign s_parity = ~(^s_data_q);
  assign s_data_index = 3'(s_bit_index_q - 1'b1);
  assign s_waiting_for_clock = (s_state_q == ST_SHIFT) || (s_state_q == ST_PARITY) ||
                               (s_state_q == ST_STOP);
  assign timeout_event_o     = enable_i && s_waiting_for_clock && !ps2_clk_fall_i &&
                               (s_timer_q + 1'b1 >= timeout_cycles_i);
  assign no_ack_event_o = enable_i && (s_state_q == ST_STOP) && ps2_clk_fall_i && ps2_dat_i;
  assign done_event_o = enable_i && (s_state_q == ST_STOP) && ps2_clk_fall_i;
  assign aborted_event_o = enable_i && active_o && abort_i;

  always_comb begin
    clk_drive_low_o = 1'b0;
    dat_drive_low_o = 1'b0;

    unique case (s_state_q)
      ST_INHIBIT: clk_drive_low_o = 1'b1;
      ST_REQUEST: begin
        clk_drive_low_o = 1'b1;
        dat_drive_low_o = 1'b1;
      end
      ST_SHIFT: begin
        if (s_bit_index_q == '0) begin
          dat_drive_low_o = 1'b1;
        end else begin
          dat_drive_low_o = !s_data_q[s_data_index];
        end
      end
      ST_PARITY:  dat_drive_low_o = !s_parity;
      default: begin
      end
    endcase
  end

  always_comb begin
    s_state_d     = s_state_q;
    s_data_d      = s_data_q;
    s_bit_index_d = s_bit_index_q;
    s_timer_d     = s_timer_q;

    if (!enable_i || abort_i || timeout_event_o) begin
      s_state_d     = ST_IDLE;
      s_data_d      = '0;
      s_bit_index_d = '0;
      s_timer_d     = '0;
    end else begin
      unique case (s_state_q)
        ST_IDLE: begin
          s_timer_d = '0;
          if (data_pop_o) begin
            s_data_d  = data_i;
            s_state_d = ST_INHIBIT;
          end
        end
        ST_INHIBIT: begin
          if (s_timer_q + 1'b1 >= inhibit_cycles_i) begin
            s_state_d = ST_REQUEST;
            s_timer_d = '0;
          end else begin
            s_timer_d = s_timer_q + 1'b1;
          end
        end
        ST_REQUEST: begin
          s_state_d     = ST_SHIFT;
          s_bit_index_d = '0;
          s_timer_d     = '0;
        end
        ST_SHIFT: begin
          if (ps2_clk_fall_i) begin
            s_timer_d = '0;
            if (s_bit_index_q == 4'd8) begin
              s_state_d = ST_PARITY;
            end else begin
              s_bit_index_d = s_bit_index_q + 1'b1;
            end
          end else begin
            s_timer_d = s_timer_q + 1'b1;
          end
        end
        ST_PARITY: begin
          if (ps2_clk_fall_i) begin
            s_state_d = ST_STOP;
            s_timer_d = '0;
          end else begin
            s_timer_d = s_timer_q + 1'b1;
          end
        end
        ST_STOP: begin
          if (ps2_clk_fall_i) begin
            s_state_d = ST_WAIT_IDLE;
            s_timer_d = '0;
          end else begin
            s_timer_d = s_timer_q + 1'b1;
          end
        end
        ST_WAIT_IDLE: begin
          if (ps2_clk_i && ps2_dat_i) begin
            s_state_d = ST_IDLE;
          end
        end
        default: s_state_d = ST_IDLE;
      endcase
    end
  end

  dffercn #(
      .REG_TYPE (state_t),
      .RESET_VAL(ST_IDLE)
  ) u_state_dffercn (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_state_d),
      .dat_o  (s_state_q)
  );

  dffer #(
      .DATA_WIDTH(8)
  ) u_data_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_data_d),
      .dat_o  (s_data_q)
  );

  dffer #(
      .DATA_WIDTH(4)
  ) u_bit_index_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_bit_index_d),
      .dat_o  (s_bit_index_q)
  );

  dffer #(
      .DATA_WIDTH(24)
  ) u_timer_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_timer_d),
      .dat_o  (s_timer_q)
  );

endmodule
