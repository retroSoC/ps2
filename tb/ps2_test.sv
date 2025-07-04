// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// ps2 is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "ps2_define.svh"

class PS2Test extends APB4Master;
  string                        name;
  bit                    [10:0] ps2_send_buf;
  int                           ps2_cnt;
  int                           ps2_clk_peroid;
  int                           wr_val;
  virtual apb4_if.master        apb4;
  virtual ps2_if.tb             ps2;

  extern function new(string name = "ps2_test", virtual apb4_if.master apb4, virtual ps2_if.tb ps2);
  extern task automatic init_ps2();
  extern task automatic kdb_sendcode(input bit [7:0] code);
  extern task automatic test_reset_reg();
  extern task automatic test_wr_rd_reg(input bit [31:0] run_times = 1000);
  extern task automatic test_rd_code(input bit [31:0] run_times = 1000);
  extern task automatic test_irq(input bit [31:0] run_times = 6);
endclass

function PS2Test::new(string name, virtual apb4_if.master apb4, virtual ps2_if.tb ps2);
  super.new("apb4_master", apb4);
  this.name           = name;
  this.ps2_send_buf   = '0;
  this.ps2_cnt        = '0;
  this.ps2_clk_peroid = 60;
  this.wr_val         = '0;
  this.apb4           = apb4;
  this.ps2            = ps2;
endfunction

task automatic PS2Test::init_ps2();
  this.ps2.ps2_clk_i = 1'b1;
  this.ps2.ps2_dat_i = 1'b1;
endtask

task automatic PS2Test::kdb_sendcode(input bit [7:0] code);
  this.ps2_send_buf[0]   = 1'b0;  // start
  this.ps2_send_buf[8:1] = code;  // code
  this.ps2_send_buf[9]   = ~(^code);  // odd parity
  this.ps2_send_buf[10]  = 1'b1;  // stop

  this.ps2_cnt           = '0;
  while (this.ps2_cnt < 11) begin
    this.ps2.ps2_dat_i = this.ps2_send_buf[this.ps2_cnt];
    #(this.ps2_clk_peroid / 2) this.ps2.ps2_clk_i = 1'b0;
    #(this.ps2_clk_peroid / 2) this.ps2.ps2_clk_i = 1'b1;
    this.ps2_cnt++;
  end
endtask

task automatic PS2Test::test_reset_reg();
  super.test_reset_reg();
  // verilog_format: off
  this.rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b0 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL, Helper::INFO);
  this.rd_check(`PS2_STAT_ADDR, "STAT REG", 32'b0 & {`PS2_STAT_WIDTH{1'b1}}, Helper::EQUL, Helper::INFO);
  // verilog_format: on
endtask

task automatic PS2Test::test_wr_rd_reg(input bit [31:0] run_times = 1000);
  super.test_wr_rd_reg();
  // verilog_format: off
  for (int i = 0; i < run_times; i++) begin
    this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", $random & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
  end
  // verilog_format: on
endtask

task automatic PS2Test::test_rd_code(input bit [31:0] run_times = 1000);
  $display("=== [test rd kdb code] ===");
  this.read(`PS2_STAT_ADDR);  // clear irq
  this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b10 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
  for (int i = 0; i < run_times; i++) begin
    this.wr_val = $random & 8'hFF;
    this.init_ps2();
    this.kdb_sendcode(this.wr_val);
    #20;
    this.rd_check(`PS2_DATA_ADDR, "DATA REG", this.wr_val, Helper::EQUL);
  end
  this.kdb_sendcode(8'h76);
  this.rd_check(`PS2_DATA_ADDR, "DATA REG", this.wr_val, Helper::EQUL);
  this.kdb_sendcode(8'h0F);
  this.kdb_sendcode(8'h76);

endtask

task automatic PS2Test::test_irq(input bit [31:0] run_times = 6);
  super.test_irq();
  this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b00 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
  this.read(`PS2_STAT_ADDR);  // clear irq
  this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b10 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
  for (int i = 0; i < run_times; i++) begin
    this.wr_val = $random & 8'hFF;
    this.init_ps2();
    this.kdb_sendcode(this.wr_val);
    $display("%t wr val: %h", $time, this.wr_val);
    repeat (60) @(posedge this.apb4.pclk);
  end

  this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b11 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
  for (int i = 0; i < run_times; i++) begin
    wait (this.ps2.irq_o);
    this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b10 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
    this.read(`PS2_DATA_ADDR);
    $display("%t data reg: %h", $time, super.rd_data);
    this.read(`PS2_STAT_ADDR);  // clear irq
    this.wr_rd_check(`PS2_CTRL_ADDR, "CTRL REG", 32'b11 & {`PS2_CTRL_WIDTH{1'b1}}, Helper::EQUL);
    repeat (17) @(posedge this.apb4.pclk);
  end

endtask
