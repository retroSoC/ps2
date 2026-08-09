// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps
`include "ps2_define.svh"

module ps2_tb;

  logic        clk;
  logic        rst_n;
  logic [11:0] paddr;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [31:0] pwdata;
  logic [ 3:0] pstrb;
  logic        pready;
  logic [31:0] prdata;
  logic        pslverr;
  logic        ps2_clk_i;
  logic        ps2_clk_o;
  logic        ps2_clk_oe;
  logic        ps2_dat_i;
  logic        ps2_dat_o;
  logic        ps2_dat_oe;
  logic        irq;
  logic [31:0] value;
  logic [ 7:0] host_data;

  tri1         ps2_clk_line;
  tri1         ps2_dat_line;

  assign ps2_clk_line = ps2_clk_oe ? ps2_clk_o : 1'bz;
  assign ps2_dat_line = ps2_dat_oe ? ps2_dat_o : 1'bz;
  assign ps2_clk_i    = ps2_clk_line;
  assign ps2_dat_i    = ps2_dat_line;

  always #5 clk = ~clk;

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
      .ps2_clk_i   (ps2_clk_i),
      .ps2_clk_o   (ps2_clk_o),
      .ps2_clk_oe_o(ps2_clk_oe),
      .ps2_dat_i   (ps2_dat_i),
      .ps2_dat_o   (ps2_dat_o),
      .ps2_dat_oe_o(ps2_dat_oe),
      .irq_o       (irq)
  );

  ps2_device_model #(
      .HALF_PERIOD_NS(200)
  ) u_device (
      .ps2_clk_io(ps2_clk_line),
      .ps2_dat_io(ps2_dat_line)
  );

  task automatic apb_write(input logic [11:0] addr, input logic [31:0] data, input logic [3:0] strb,
                           input logic expected_error);
    @(negedge clk);
    paddr   = addr;
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b1;
    pwdata  = data;
    pstrb   = strb;
    @(negedge clk);
    penable = 1'b1;
    #1;
    if (!pready || (pslverr != expected_error)) begin
      $fatal(1, "APB write mismatch addr=%h error=%b expected=%b", addr, pslverr, expected_error);
    end
    @(negedge clk);
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    pwdata  = '0;
    pstrb   = '0;
  endtask

  task automatic apb_read(input logic [11:0] addr, output logic [31:0] data,
                          input logic expected_error);
    @(negedge clk);
    paddr   = addr;
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b0;
    pstrb   = '0;
    @(negedge clk);
    penable = 1'b1;
    #1;
    data = prdata;
    if (!pready || (pslverr != expected_error)) begin
      $fatal(1, "APB read mismatch addr=%h error=%b expected=%b", addr, pslverr, expected_error);
    end
    @(negedge clk);
    psel    = 1'b0;
    penable = 1'b0;
  endtask

  initial begin
    clk     = 1'b0;
    rst_n   = 1'b0;
    paddr   = '0;
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    pwdata  = '0;
    pstrb   = '0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (6) @(negedge clk);

    apb_read(`PS2_IP_ID_OFFSET, value, 1'b0);
    if (value != `PS2_IP_ID_VALUE) $fatal(1, "IP ID mismatch");
    apb_read(`PS2_IP_VERSION_OFFSET, value, 1'b0);
    if (value != `PS2_IP_VERSION_VALUE) $fatal(1, "IP version mismatch");
    apb_read(12'h003, value, 1'b1);
    apb_read(12'h080, value, 1'b1);
    apb_write(`PS2_STATUS_OFFSET, 32'h1, 4'hF, 1'b1);
    apb_read(`PS2_RXDATA_OFFSET, value, 1'b0);
    if (value != '0) $fatal(1, "empty RXDATA must be zero");

    apb_write(`PS2_FILTER_OFFSET, 32'd1, 4'h1, 1'b0);
    apb_write(`PS2_INHIBIT_CYCLES_OFFSET, 32'd4, 4'hF, 1'b0);
    apb_write(`PS2_FRAME_TIMEOUT_OFFSET, 32'd100, 4'hF, 1'b0);
    apb_write(`PS2_RX_WATERMARK_OFFSET, 32'd1, 4'h1, 1'b0);
    apb_write(`PS2_TX_WATERMARK_OFFSET, 32'd0, 4'h1, 1'b0);
    apb_write(`PS2_INTR_ENABLE_OFFSET, `PS2_INTR_VALID_MASK, 4'hF, 1'b0);
    apb_write(`PS2_CTRL_OFFSET, `PS2_CTRL_ENABLE_MASK, 4'h1, 1'b0);
    apb_write(`PS2_FILTER_OFFSET, 32'd2, 4'h1, 1'b1);

    u_device.send_byte(8'h1C, 3'b000);
    repeat (10) @(negedge clk);
    apb_read(`PS2_RXDATA_OFFSET, value, 1'b0);
    if (!value[15] || (value[7:0] != 8'h1C) || (value[10:8] != '0)) begin
      $fatal(1, "valid RX frame mismatch: %h", value);
    end

    u_device.send_byte(8'h55, 3'b010);
    repeat (10) @(negedge clk);
    apb_read(`PS2_RXDATA_OFFSET, value, 1'b0);
    if ((value[7:0] != 8'h55) || (value[10:8] != 3'b010)) begin
      $fatal(1, "RX parity error tag mismatch: %h", value);
    end
    apb_read(`PS2_ERROR_STATUS_OFFSET, value, 1'b0);
    if ((value & `PS2_RX_ERROR_PARITY_MASK) == '0) $fatal(1, "RX parity sticky error missing");

    fork
      u_device.receive_host_byte(host_data, 1'b1);
      apb_write(`PS2_TXDATA_OFFSET, 32'h0000_00F4, 4'h1, 1'b0);
    join
    if (host_data != 8'hF4) $fatal(1, "host TX data mismatch: %h", host_data);
    repeat (10) @(negedge clk);
    apb_read(`PS2_ERROR_STATUS_OFFSET, value, 1'b0);
    if ((value & `PS2_TX_ERROR_NO_ACK_MASK) != '0) $fatal(1, "unexpected no-ACK error");

    fork
      u_device.receive_host_byte(host_data, 1'b0);
      apb_write(`PS2_TXDATA_OFFSET, 32'h0000_00ED, 4'h1, 1'b0);
    join
    repeat (10) @(negedge clk);
    apb_read(`PS2_ERROR_STATUS_OFFSET, value, 1'b0);
    if ((value & `PS2_TX_ERROR_NO_ACK_MASK) == '0) $fatal(1, "no-ACK error missing");
    if (!irq) $fatal(1, "error interrupt missing");

    apb_write(`PS2_ERROR_STATUS_OFFSET, `PS2_ERROR_VALID_MASK, 4'hF, 1'b0);
    apb_write(`PS2_INTR_STATE_OFFSET, `PS2_INTR_VALID_MASK, 4'hF, 1'b0);
    apb_write(`PS2_FIFO_CTRL_OFFSET, `PS2_FIFO_CTRL_RX_FLUSH_MASK | `PS2_FIFO_CTRL_TX_FLUSH_MASK,
              4'h1, 1'b0);
    apb_write(`PS2_CTRL_OFFSET, 32'h0, 4'h1, 1'b0);
    repeat (3) @(negedge clk);
    if (ps2_clk_oe || ps2_dat_oe) $fatal(1, "disabled controller did not release lines");

    $display("PS2_TEST_PASS");
    $finish;
  end

endmodule
