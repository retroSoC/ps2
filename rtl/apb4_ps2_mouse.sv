// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// ps2 is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

/*
module apb4_ps2_mouse (
    // verilog_format: off
    apb4_if.slave apb4,
    // verilog_format: on
    input  logic  ps2_clk_i,
    output logic  ps2_clk_o,
    output logic  ps2_clk_oen_o,
    input  logic  ps2_dat_i,
    output logic  ps2_dat_o,
    output logic  ps2_dat_oen_o,
    output logic  irq_o
);

  logic [23:0] r_fifo[0:7];
  logic [2:0] r_wr_ptr, r_rd_ptr;
  logic [ 9:0] r_buf;
  logic [ 3:0] r_cnt;
  logic [ 2:0] r_clk_sync;
  logic        s_negedge;
  logic [23:0] r_rd_dat;

  assign s_negedge = r_clk_sync[2] & (~r_clk_sync[1]);
  always_ff @(posedge apb4.hclk) begin
    r_clk_sync <= {r_clk_sync[1:0], ps2_clk_i};
  end

  always_ff @(posedge apb4.hclk) begin
    if (~abp4.hresetn) begin
      r_cnt    <= '0;
      r_wr_ptr <= '0;
    end else begin
      if (s_negedge) begin
        if (r_cnt == 4'd10) begin
          if ((r_buf[0] == 0) && ps2_dat_i && (^r_buf[9:1])) begin
            r_fifo[r_wr_ptr] <= r_buf[8:1];
            r_wr_ptr         <= r_wr_ptr + 1'b1;
            irq_o            <= 1'b1;  // NOTE: BUG
          end
          r_cnt <= '0;
        end else begin
          r_buf[r_cnt] <= ps2_dat_i;
          r_cnt        <= r_cnt + 1'b1;
        end
      end
    end
  end

  assign apb4.prdata = {24'b0, r_rd_dat};
  always_ff @(posedge apb4.hclk, negedge abp4.hresetn) begin
    if (~apb4.hresetn) begin
      r_rd_ptr <= '0;
      r_rd_dat <= '0;
      irq_o    <= '0;
    end else if ((apb4.psel && apb4.penable) && (~apb4.pwrite)) begin
      r_rd_dat <= (r_rd_ptr == r_wr_ptr) ? '0 : r_fifo[r_rd_ptr];
      r_rd_ptr <= (r_rd_ptr == r_wr_ptr) ? r_rd_ptr : r_rd_ptr + 1'b1;
      irq_o    <= (r_rd_ptr == r_wr_ptr) ? irq_o : 1'b0;
    end
  end

  assign apb4.pready = 1'b1;
  assign apb4.pslerr = 1'b0;

endmodule
*/
