// FILE COPIED FROM EXERCISE 1

// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// gives us the `FF(...) macro making it easy to have properly defined flip-flops
`include "common_cells/registers.svh"

// Popcount accumulator user module
// Counts the number of bits set to 1 in the written data and accumulates it
// Provides the accumulated count when read
module user_popcount_acc #(
  parameter obi_pkg::obi_cfg_t ObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter type               obi_req_t = logic,
  parameter type               obi_rsp_t = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o
);

  // Define some registers to hold the requests fields
  logic req_d, req_q;
  logic we_d, we_q;
  logic [ObiCfg.AddrWidth-1:0] addr_d, addr_q;
  logic [  ObiCfg.IdWidth-1:0] id_d, id_q;
  logic [ObiCfg.DataWidth-1:0] wdata_d, wdata_q;

  // Signals used to create the response
  logic [ObiCfg.DataWidth-1:0] rsp_data; // Data field of the obi response
  logic rsp_err;                         // Error field of the obi response

  // Internal signals/registers
  logic [15:0] popcnt_acc_d, popcnt_acc_q; // Holds the accumulated popcount
  logic [15:0] wdata_cnt;                  // Holds the popcount of the previous cycle's request wdata

  // Note: to avoid writing trivial always_ff statements we can use this macro defined in registers.svh
  `FF(req_q, req_d, '0);
  `FF(id_q, id_d, '0);
  `FF(we_q, we_d, '0);
  `FF(wdata_q, wdata_d, '0);
  `FF(addr_q, addr_d, '0);
  `FF(popcnt_acc_q, popcnt_acc_d, '0);

  assign req_d   = obi_req_i.req;
  assign id_d    = obi_req_i.a.aid;
  assign we_d    = obi_req_i.a.we;
  assign addr_d  = obi_req_i.a.addr;
  assign wdata_d = obi_req_i.a.wdata;

  // TODO 2: Build wdata_cnt, which counts the number of bits set to 1
  // in the previous cycle's request data
  always_comb begin
    wdata_cnt = 16'h0;
    for (int i = 0;i< ObiCfg.DataWidth; i++) begin
      wdata_cnt = wdata_cnt + wdata_q[i];
    end
  end // done

  // Assign the response data
  always_comb begin
    rsp_data = '0;
    rsp_err  = '0;
    popcnt_acc_d = popcnt_acc_q;

    // TODO 1: A write request at address 0x0 will set the accumulator to zero
    if(req_q) begin
      case(addr_q[3:2])
        2'h0: begin
          popcnt_acc_d = 0; // done
        end  
        2'h1: begin
          if(we_q) begin
            popcnt_acc_d = popcnt_acc_q + wdata_cnt;
          end else begin
            rsp_err = '1;
          end
        end
        2'h2: begin
          if(we_q) begin
            rsp_err = '1;
          end else begin
            rsp_data = popcnt_acc_q;
          end
        end
        default: rsp_data = 32'hffffffff;
      endcase
    end
  end

  // Assign the response
  // A channel
  assign obi_rsp_o.gnt = obi_req_i.req;
  // R channel
  assign obi_rsp_o.rvalid       = req_q;
  assign obi_rsp_o.r.rdata      = rsp_data;
  assign obi_rsp_o.r.rid        = id_q;
  assign obi_rsp_o.r.err        = rsp_err;
  assign obi_rsp_o.r.r_optional = '0;

endmodule
