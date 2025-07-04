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

// only support keyboard now
module apb4_ps2 (
    apb4_if.slave apb4,
    ps2_if.dut    ps2
);

  logic [3:0] s_apb4_addr;
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic [`PS2_CTRL_WIDTH-1:0] s_ps2_ctrl_d, s_ps2_ctrl_q;
  logic s_ps2_ctrl_en;
  logic [`PS2_STAT_WIDTH-1:0] s_ps2_stat_d, s_ps2_stat_q;
  logic s_ps2_stat_en;
  logic [3:0] s_cnt_d, s_cnt_q;
  logic [9:0] s_dat_d, s_dat_q;
  logic s_fifo_empty, s_fifo_push_valid;
  logic [7:0] s_fifo_rd_dat;
  logic s_bit_itn, s_bit_en, s_bit_itf, s_clk_fe, s_irq_trg;

  assign s_apb4_addr     = apb4.paddr[5:2];
  assign s_apb4_wr_hdshk = apb4.psel && apb4.penable && apb4.pwrite;
  assign s_apb4_rd_hdshk = apb4.psel && apb4.penable && (~apb4.pwrite);
  assign apb4.pready     = 1'b1;
  assign apb4.pslverr    = 1'b0;

  assign s_bit_itn       = s_ps2_ctrl_q[0];
  assign s_bit_en        = s_ps2_ctrl_q[1];
  assign s_bit_itf       = s_ps2_stat_q[0];
  assign ps2.irq_o       = s_bit_itf;

  assign s_ps2_ctrl_en   = s_apb4_wr_hdshk && s_apb4_addr == `PS2_CTRL;
  assign s_ps2_ctrl_d    = apb4.pwdata[`PS2_CTRL_WIDTH-1:0];
  dffer #(`PS2_CTRL_WIDTH) u_ps2_ctrl_dffer (
      apb4.pclk,
      apb4.presetn,
      s_ps2_ctrl_en,
      s_ps2_ctrl_d,
      s_ps2_ctrl_q
  );

  edge_det_fe #(2, 1) u_ps2_clk_edge_det_fe (
      apb4.pclk,
      apb4.presetn,
      ps2.ps2_clk_i,
      s_clk_fe
  );

  always_comb begin
    s_cnt_d = s_cnt_q;
    if (~s_bit_en) begin
      s_cnt_d = '0;
    end else if (s_clk_fe) begin
      if (s_cnt_q == 4'd10) begin
        s_cnt_d = '0;
      end else begin
        s_cnt_d = s_cnt_q + 1'b1;
      end
    end
  end
  dffer #(4) u_cnt_dffer (
      apb4.pclk,
      apb4.presetn,
      s_clk_fe,
      s_cnt_d,
      s_cnt_q
  );

  always_comb begin
    s_dat_d = s_dat_q;
    if (s_bit_en && s_clk_fe) begin
      if (s_cnt_q < 4'd10) begin
        s_dat_d[s_cnt_q] = ps2.ps2_dat_i;
      end
    end
  end
  dffer #(10) u_dat_dffer (
      apb4.pclk,
      apb4.presetn,
      s_clk_fe,
      s_dat_d,
      s_dat_q
  );

  always_comb begin
    s_fifo_push_valid = 1'b0;
    if (s_bit_en && s_clk_fe) begin
      if (s_cnt_q == 4'd10) begin
        if (s_dat_q[0] == 1'b0 && ps2.ps2_dat_i && (^s_dat_q[9:1])) begin
          s_fifo_push_valid = 1'b1;
        end
      end
    end
  end
  fifo #(
      .DATA_WIDTH  (8),
      .BUFFER_DEPTH(8)
  ) u_ps2_fifo (
      .clk_i  (apb4.pclk),
      .rst_n_i(apb4.presetn),
      .flush_i(~s_bit_en),
      .full_o (),
      .empty_o(s_fifo_empty),
      .cnt_o  (),
      .dat_i  (s_dat_q[8:1]),
      .push_i (s_fifo_push_valid),
      .dat_o  (s_fifo_rd_dat),
      .pop_i  (s_apb4_rd_hdshk && s_apb4_addr == `PS2_DATA)
  );

  assign s_irq_trg = ~s_fifo_empty;
  assign s_ps2_stat_en = (s_bit_itf && s_apb4_rd_hdshk && s_apb4_addr == `PS2_STAT) || (~s_bit_itf && s_bit_en && s_bit_itn && s_irq_trg);
  always_comb begin
    s_ps2_stat_d = s_ps2_stat_q;
    if (s_bit_itf && s_apb4_rd_hdshk && s_apb4_addr == `PS2_STAT) begin
      s_ps2_stat_d = '0;
    end else if (~s_bit_itf && s_bit_en && s_bit_itn && s_irq_trg) begin
      s_ps2_stat_d = '1;
    end
  end
  dffer #(`PS2_STAT_WIDTH) u_ps2_stat_dffer (
      apb4.pclk,
      apb4.presetn,
      s_ps2_stat_en,
      s_ps2_stat_d,
      s_ps2_stat_q
  );

  // verilog_format: off
  always_comb begin
    apb4.prdata = '0;
    if (s_apb4_rd_hdshk) begin
      unique case (s_apb4_addr)
        `PS2_CTRL: apb4.prdata[`PS2_CTRL_WIDTH-1:0] = s_ps2_ctrl_q;
        `PS2_DATA: apb4.prdata[`PS2_DATA_WIDTH-1:0] = (s_fifo_empty || ~s_bit_en) ? '0 : s_fifo_rd_dat;
        `PS2_STAT: apb4.prdata[`PS2_STAT_WIDTH-1:0] = s_ps2_stat_q;
        default:   apb4.prdata = '0;
      endcase
    end
  end
  // verilog_format: on
endmodule
