// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps

module ps2_device_model (
    inout wire ps2_clk_io,
    inout wire ps2_dat_io
);

  parameter int HALF_PERIOD_NS = 200;

  logic r_clk_drive_low;
  logic r_dat_drive_low;

  assign ps2_clk_io = r_clk_drive_low ? 1'b0 : 1'bz;
  assign ps2_dat_io = r_dat_drive_low ? 1'b0 : 1'bz;

  initial begin
    r_clk_drive_low = 1'b0;
    r_dat_drive_low = 1'b0;
  end

  task automatic pulse_clock;
    #(HALF_PERIOD_NS);
    r_clk_drive_low = 1'b1;
    #(HALF_PERIOD_NS);
    r_clk_drive_low = 1'b0;
  endtask

  task automatic send_byte(input logic [7:0] data, input logic [2:0] error);
    logic [10:0] frame;
    frame[0]   = error[0];
    frame[8:1] = data;
    frame[9]   = (~^data) ^ error[1];
    frame[10]  = !error[2];

    for (int bit_idx = 0; bit_idx < 11; bit_idx++) begin
      r_dat_drive_low = !frame[bit_idx];
      pulse_clock();
    end
    r_dat_drive_low = 1'b0;
    #(HALF_PERIOD_NS);
  endtask

  task automatic receive_host_byte(output logic [7:0] data, input logic acknowledge);
    logic [11:0] frame;

    wait ((ps2_clk_io === 1'b0) && (ps2_dat_io === 1'b0));
    frame[0] = ps2_dat_io;
    wait (ps2_clk_io === 1'b1);
    for (int bit_idx = 1; bit_idx < 11; bit_idx++) begin
      #(HALF_PERIOD_NS);
      r_clk_drive_low = 1'b1;
      #(HALF_PERIOD_NS);
      r_clk_drive_low = 1'b0;
      #(HALF_PERIOD_NS / 2);
      frame[bit_idx] = ps2_dat_io;
      #(HALF_PERIOD_NS / 2);
    end
    r_dat_drive_low = acknowledge;
    pulse_clock();
    r_dat_drive_low = 1'b0;
    data            = frame[8:1];

    if (frame[0] != 1'b0 || frame[10] != 1'b1 || !(^frame[9:1])) begin
      $fatal(1, "host frame invalid: %b", frame[10:0]);
    end
  endtask

endmodule
