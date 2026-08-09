// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ps2_define.svh"

module ps2_reg #(
    parameter int PCLK_HZ       = 72_000_000,
    parameter int RX_FIFO_DEPTH = 16,
    parameter int TX_FIFO_DEPTH = 16
) (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [11:0] paddr_i,
    input  logic        psel_i,
    input  logic        penable_i,
    input  logic        pwrite_i,
    input  logic [31:0] pwdata_i,
    input  logic [ 3:0] pstrb_i,
    output logic        pready_o,
    output logic [31:0] prdata_o,
    output logic        pslverr_o,
    input  logic        ps2_clk_i,
    output logic        ps2_clk_o,
    output logic        ps2_clk_oe_o,
    input  logic        ps2_dat_i,
    output logic        ps2_dat_o,
    output logic        ps2_dat_oe_o,
    output logic        irq_o
    // verilog_format: on
);

  localparam logic [63:0] PCLK_HZ_VALUE = 64'(PCLK_HZ);
  localparam logic [63:0] DEFAULT_INHIBIT_VALUE =
      ((PCLK_HZ_VALUE * 64'd120) + 64'd999_999) / 64'd1_000_000;
  localparam logic [63:0] DEFAULT_TIMEOUT_VALUE =
      ((PCLK_HZ_VALUE * 64'd2_000) + 64'd999_999) / 64'd1_000_000;
  localparam logic [7:0] RX_FIFO_DEPTH_VALUE = 8'(RX_FIFO_DEPTH);
  localparam logic [7:0] TX_FIFO_DEPTH_VALUE = 8'(TX_FIFO_DEPTH);
  localparam logic [31:0] CAPABILITY_VALUE = {
    `PS2_ABI_VERSION, RX_FIFO_DEPTH_VALUE, TX_FIFO_DEPTH_VALUE, `PS2_CAPABILITY_FEATURES
  };

  logic        s_transfer;
  logic        s_read;
  logic        s_write;
  logic        s_access_legal;
  logic [31:0] s_write_mask;
  logic [31:0] s_masked_wdata;
  logic [31:0] s_ctrl_merged;
  logic [31:0] s_rx_watermark_merged;
  logic [31:0] s_tx_watermark_merged;
  logic [31:0] s_filter_merged;
  logic [31:0] s_inhibit_merged;
  logic [31:0] s_timeout_merged;
  logic [31:0] s_intr_enable_merged;

  logic s_enable_d, s_enable_q;
  logic [7:0] s_rx_watermark_d, s_rx_watermark_q;
  logic [7:0] s_tx_watermark_d, s_tx_watermark_q;
  logic [3:0] s_filter_cycles_d, s_filter_cycles_q;
  logic [23:0] s_inhibit_cycles_d, s_inhibit_cycles_q;
  logic [23:0] s_frame_timeout_d, s_frame_timeout_q;
  logic [8:0] s_error_status_d, s_error_status_q;
  logic [5:0] s_intr_state_d, s_intr_state_q;
  logic [5:0] s_intr_enable_d, s_intr_enable_q;

  logic        s_soft_reset;
  logic        s_abort_tx;
  logic        s_flush_rx;
  logic        s_flush_tx;
  logic        s_rx_pop;
  logic        s_tx_push;
  logic [10:0] s_rx_data;
  logic [ 7:0] s_rx_level;
  logic        s_rx_empty;
  logic        s_rx_full;
  logic [ 7:0] s_tx_level;
  logic        s_tx_empty;
  logic        s_tx_full;
  logic        s_rx_active;
  logic        s_tx_active;
  logic [ 8:0] s_error_event;
  logic        s_tx_done_event;
  logic        s_filtered_clk;
  logic        s_filtered_dat;
  logic [ 5:0] s_intr_event;

  initial begin
    if ((PCLK_HZ < 1_000_000) || (DEFAULT_INHIBIT_VALUE == 0) ||
        (DEFAULT_INHIBIT_VALUE > 64'h00FF_FFFF) || (DEFAULT_TIMEOUT_VALUE == 0) ||
        (DEFAULT_TIMEOUT_VALUE > 64'h00FF_FFFF)) begin
      $fatal(1, "ps2_reg: PCLK_HZ produces an unsupported timing configuration");
    end
  end

  assign s_transfer = psel_i && penable_i;
  assign s_read = s_transfer && !pwrite_i;
  assign s_write = s_transfer && pwrite_i;
  assign s_write_mask = {{8{pstrb_i[3]}}, {8{pstrb_i[2]}}, {8{pstrb_i[1]}}, {8{pstrb_i[0]}}};
  assign s_masked_wdata = pwdata_i & s_write_mask;

  assign s_ctrl_merged = ({31'h0, s_enable_q} & ~s_write_mask) | s_masked_wdata;
  assign s_rx_watermark_merged = ({24'h0, s_rx_watermark_q} & ~s_write_mask) | s_masked_wdata;
  assign s_tx_watermark_merged = ({24'h0, s_tx_watermark_q} & ~s_write_mask) | s_masked_wdata;
  assign s_filter_merged = ({28'h0, s_filter_cycles_q} & ~s_write_mask) | s_masked_wdata;
  assign s_inhibit_merged = ({8'h0, s_inhibit_cycles_q} & ~s_write_mask) | s_masked_wdata;
  assign s_timeout_merged = ({8'h0, s_frame_timeout_q} & ~s_write_mask) | s_masked_wdata;
  assign s_intr_enable_merged = ({26'h0, s_intr_enable_q} & ~s_write_mask) | s_masked_wdata;

  assign pready_o = 1'b1;
  assign ps2_clk_o = 1'b0;
  assign ps2_dat_o = 1'b0;

  always_comb begin
    prdata_o       = '0;
    s_access_legal = paddr_i[1:0] == 2'b00;

    if (s_read && s_access_legal) begin
      unique case (paddr_i)
        `PS2_CTRL_OFFSET:           prdata_o = {31'h0, s_enable_q};
        `PS2_STATUS_OFFSET: begin
          prdata_o = {
            19'h0,
            1'b1,
            ps2_dat_oe_o,
            ps2_clk_oe_o,
            s_filtered_dat,
            s_filtered_clk,
            s_tx_full,
            s_tx_empty,
            s_rx_full,
            s_rx_empty,
            s_tx_active,
            s_rx_active,
            s_filtered_clk && s_filtered_dat && !s_rx_active && !s_tx_active,
            s_enable_q
          };
        end
        `PS2_RXDATA_OFFSET: begin
          if (!s_rx_empty) begin
            prdata_o = {8'h00, s_rx_level, 1'b1, 4'h0, s_rx_data[10:8], s_rx_data[7:0]};
          end
        end
        `PS2_FIFO_STATUS_OFFSET: begin
          prdata_o = {TX_FIFO_DEPTH_VALUE, RX_FIFO_DEPTH_VALUE, s_tx_level, s_rx_level};
        end
        `PS2_RX_WATERMARK_OFFSET:   prdata_o = {24'h0, s_rx_watermark_q};
        `PS2_TX_WATERMARK_OFFSET:   prdata_o = {24'h0, s_tx_watermark_q};
        `PS2_FILTER_OFFSET:         prdata_o = {28'h0, s_filter_cycles_q};
        `PS2_INHIBIT_CYCLES_OFFSET: prdata_o = {8'h0, s_inhibit_cycles_q};
        `PS2_FRAME_TIMEOUT_OFFSET:  prdata_o = {8'h0, s_frame_timeout_q};
        `PS2_ERROR_STATUS_OFFSET:   prdata_o = {23'h0, s_error_status_q};
        `PS2_INTR_STATE_OFFSET:     prdata_o = {26'h0, s_intr_state_q};
        `PS2_INTR_ENABLE_OFFSET:    prdata_o = {26'h0, s_intr_enable_q};
        `PS2_IP_ID_OFFSET:          prdata_o = `PS2_IP_ID_VALUE;
        `PS2_IP_VERSION_OFFSET:     prdata_o = `PS2_IP_VERSION_VALUE;
        `PS2_CAPABILITY_OFFSET:     prdata_o = CAPABILITY_VALUE;
        default: begin
          prdata_o       = '0;
          s_access_legal = 1'b0;
        end
      endcase
    end else if (s_write && s_access_legal) begin
      unique case (paddr_i)
        `PS2_CTRL_OFFSET: begin
          s_access_legal = (s_ctrl_merged & ~`PS2_CTRL_VALID_MASK) == '0;
        end
        `PS2_TXDATA_OFFSET: begin
          s_access_legal = s_enable_q && !s_tx_full && pstrb_i[0] &&
                           ((s_masked_wdata & 32'hFFFF_FF00) == '0);
        end
        `PS2_FIFO_CTRL_OFFSET: begin
          s_access_legal = (s_masked_wdata & ~`PS2_FIFO_CTRL_VALID_MASK) == '0;
        end
        `PS2_RX_WATERMARK_OFFSET: begin
          s_access_legal = !s_enable_q && ((s_rx_watermark_merged & 32'hFFFF_FF00) == '0) &&
                           (s_rx_watermark_merged[7:0] >= 1) &&
                           (s_rx_watermark_merged[7:0] <= RX_FIFO_DEPTH_VALUE);
        end
        `PS2_TX_WATERMARK_OFFSET: begin
          s_access_legal = !s_enable_q && ((s_tx_watermark_merged & 32'hFFFF_FF00) == '0) &&
                           (s_tx_watermark_merged[7:0] <= TX_FIFO_DEPTH_VALUE);
        end
        `PS2_FILTER_OFFSET: begin
          s_access_legal = !s_enable_q && ((s_filter_merged & 32'hFFFF_FFF0) == '0) &&
                           (s_filter_merged[3:0] >= 1);
        end
        `PS2_INHIBIT_CYCLES_OFFSET: begin
          s_access_legal = !s_enable_q && ((s_inhibit_merged & 32'hFF00_0000) == '0) &&
                           (s_inhibit_merged[23:0] >= 1);
        end
        `PS2_FRAME_TIMEOUT_OFFSET: begin
          s_access_legal = !s_enable_q && ((s_timeout_merged & 32'hFF00_0000) == '0) &&
                           (s_timeout_merged[23:0] >= 1);
        end
        `PS2_COMMAND_OFFSET: begin
          s_access_legal = (s_masked_wdata & ~`PS2_COMMAND_VALID_MASK) == '0;
        end
        `PS2_ERROR_STATUS_OFFSET: begin
          s_access_legal = (s_masked_wdata & ~`PS2_ERROR_VALID_MASK) == '0;
        end
        `PS2_INTR_STATE_OFFSET: begin
          s_access_legal = (s_masked_wdata & ~`PS2_INTR_VALID_MASK) == '0;
        end
        `PS2_INTR_ENABLE_OFFSET: begin
          s_access_legal = (s_intr_enable_merged & ~`PS2_INTR_VALID_MASK) == '0;
        end
        `PS2_INTR_TEST_OFFSET: begin
          s_access_legal = (s_masked_wdata & ~`PS2_INTR_VALID_MASK) == '0;
        end
        default: s_access_legal = 1'b0;
      endcase
    end else if (s_transfer) begin
      s_access_legal = 1'b0;
    end
  end

  assign pslverr_o = s_transfer && !s_access_legal;
  assign s_rx_pop = s_read && s_access_legal && (paddr_i == `PS2_RXDATA_OFFSET) && !s_rx_empty;
  assign s_tx_push = s_write && s_access_legal && (paddr_i == `PS2_TXDATA_OFFSET);
  assign s_flush_rx =
      s_write && s_access_legal && (paddr_i == `PS2_FIFO_CTRL_OFFSET) &&
      ((s_masked_wdata & `PS2_FIFO_CTRL_RX_FLUSH_MASK) != '0);
  assign s_flush_tx =
      s_write && s_access_legal && (paddr_i == `PS2_FIFO_CTRL_OFFSET) &&
      ((s_masked_wdata & `PS2_FIFO_CTRL_TX_FLUSH_MASK) != '0);
  assign s_abort_tx =
      s_write && s_access_legal && (paddr_i == `PS2_COMMAND_OFFSET) &&
      ((s_masked_wdata & `PS2_COMMAND_ABORT_MASK) != '0);
  assign s_soft_reset =
      s_write && s_access_legal && (paddr_i == `PS2_COMMAND_OFFSET) &&
      ((s_masked_wdata & `PS2_COMMAND_SOFT_RESET_MASK) != '0);

  assign s_intr_event[0] = s_enable_q && (s_rx_level >= s_rx_watermark_q);
  assign s_intr_event[1] = s_enable_q && (s_tx_level <= s_tx_watermark_q);
  assign s_intr_event[2] = s_tx_done_event;
  assign s_intr_event[3] = |s_error_event[4:0];
  assign s_intr_event[4] = |s_error_event[7:5];
  assign s_intr_event[5] = s_error_event[8];

  always_comb begin
    s_enable_d         = s_enable_q;
    s_rx_watermark_d   = s_rx_watermark_q;
    s_tx_watermark_d   = s_tx_watermark_q;
    s_filter_cycles_d  = s_filter_cycles_q;
    s_inhibit_cycles_d = s_inhibit_cycles_q;
    s_frame_timeout_d  = s_frame_timeout_q;
    s_error_status_d   = s_error_status_q | s_error_event;
    s_intr_state_d     = s_intr_state_q | s_intr_event;
    s_intr_enable_d    = s_intr_enable_q;

    if (s_write && s_access_legal) begin
      unique case (paddr_i)
        `PS2_CTRL_OFFSET:           s_enable_d = s_ctrl_merged[0];
        `PS2_RX_WATERMARK_OFFSET:   s_rx_watermark_d = s_rx_watermark_merged[7:0];
        `PS2_TX_WATERMARK_OFFSET:   s_tx_watermark_d = s_tx_watermark_merged[7:0];
        `PS2_FILTER_OFFSET:         s_filter_cycles_d = s_filter_merged[3:0];
        `PS2_INHIBIT_CYCLES_OFFSET: s_inhibit_cycles_d = s_inhibit_merged[23:0];
        `PS2_FRAME_TIMEOUT_OFFSET:  s_frame_timeout_d = s_timeout_merged[23:0];
        `PS2_ERROR_STATUS_OFFSET:   s_error_status_d = s_error_status_d & ~s_masked_wdata[8:0];
        `PS2_INTR_STATE_OFFSET:     s_intr_state_d = s_intr_state_d & ~s_masked_wdata[5:0];
        `PS2_INTR_ENABLE_OFFSET:    s_intr_enable_d = s_intr_enable_merged[5:0];
        `PS2_INTR_TEST_OFFSET:      s_intr_state_d = s_intr_state_d | s_masked_wdata[5:0];
        default: begin
        end
      endcase
    end

    if (s_soft_reset) begin
      s_enable_d       = 1'b0;
      s_error_status_d = '0;
      s_intr_state_d   = '0;
    end
  end

  ps2_core #(
      .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
      .TX_FIFO_DEPTH(TX_FIFO_DEPTH)
  ) u_ps2_core (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .enable_i           (s_enable_q),
      .soft_reset_i       (s_soft_reset),
      .abort_tx_i         (s_abort_tx),
      .flush_rx_i         (s_flush_rx),
      .flush_tx_i         (s_flush_tx),
      .filter_cycles_i    (s_filter_cycles_q),
      .inhibit_cycles_i   (s_inhibit_cycles_q),
      .frame_timeout_i    (s_frame_timeout_q),
      .rx_pop_i           (s_rx_pop),
      .rx_data_o          (s_rx_data),
      .rx_level_o         (s_rx_level),
      .rx_empty_o         (s_rx_empty),
      .rx_full_o          (s_rx_full),
      .tx_push_i          (s_tx_push),
      .tx_data_i          (s_masked_wdata[7:0]),
      .tx_level_o         (s_tx_level),
      .tx_empty_o         (s_tx_empty),
      .tx_full_o          (s_tx_full),
      .rx_active_o        (s_rx_active),
      .tx_active_o        (s_tx_active),
      .error_event_o      (s_error_event),
      .tx_done_event_o    (s_tx_done_event),
      .ps2_clk_i          (ps2_clk_i),
      .ps2_dat_i          (ps2_dat_i),
      .ps2_clk_drive_low_o(ps2_clk_oe_o),
      .ps2_dat_drive_low_o(ps2_dat_oe_o),
      .filtered_clk_o     (s_filtered_clk),
      .filtered_dat_o     (s_filtered_dat)
  );

  dffer #(
      .DATA_WIDTH(1)
  ) u_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_enable_d),
      .dat_o  (s_enable_q)
  );

  dfferc #(
      .DATA_WIDTH(8),
      .RESET_VAL (8'd1)
  ) u_rx_watermark_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_rx_watermark_d),
      .dat_o  (s_rx_watermark_q)
  );

  dffer #(
      .DATA_WIDTH(8)
  ) u_tx_watermark_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_tx_watermark_d),
      .dat_o  (s_tx_watermark_q)
  );

  dfferc #(
      .DATA_WIDTH(4),
      .RESET_VAL (4'd3)
  ) u_filter_cycles_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_filter_cycles_d),
      .dat_o  (s_filter_cycles_q)
  );

  dfferc #(
      .DATA_WIDTH(24),
      .RESET_VAL (DEFAULT_INHIBIT_VALUE[23:0])
  ) u_inhibit_cycles_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_inhibit_cycles_d),
      .dat_o  (s_inhibit_cycles_q)
  );

  dfferc #(
      .DATA_WIDTH(24),
      .RESET_VAL (DEFAULT_TIMEOUT_VALUE[23:0])
  ) u_frame_timeout_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_frame_timeout_d),
      .dat_o  (s_frame_timeout_q)
  );

  dffer #(
      .DATA_WIDTH(9)
  ) u_error_status_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_error_status_d),
      .dat_o  (s_error_status_q)
  );

  dffer #(
      .DATA_WIDTH(6)
  ) u_intr_state_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );

  dffer #(
      .DATA_WIDTH(6)
  ) u_intr_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_intr_enable_d),
      .dat_o  (s_intr_enable_q)
  );

  assign irq_o = |(s_intr_state_q & s_intr_enable_q);

`ifdef FORMAL
  ps2_formal_props #(
      .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
      .TX_FIFO_DEPTH(TX_FIFO_DEPTH)
  ) u_ps2_formal_props (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (s_enable_q),
      .rx_level_i   (s_rx_level),
      .tx_level_i   (s_tx_level),
      .ps2_clk_o_i  (ps2_clk_o),
      .ps2_dat_o_i  (ps2_dat_o),
      .ps2_clk_oe_i (ps2_clk_oe_o),
      .ps2_dat_oe_i (ps2_dat_oe_o),
      .irq_i        (irq_o),
      .intr_state_i (s_intr_state_q),
      .intr_enable_i(s_intr_enable_q)
  );
`endif

endmodule
