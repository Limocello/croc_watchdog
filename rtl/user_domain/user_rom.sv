// FILE COPIED FROM EXERCISE 1

// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Cyril Koenig <cykoenig@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

// Simple ROM
module user_rom #(
  // The OBI configuration for all ports
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
  logic req_d, req_q;                          // Request valid
  logic we_d, we_q;                            // Write enable
  logic [ObiCfg.AddrWidth-1:0] addr_d, addr_q; // Internal address of the word to read
  logic [ObiCfg.IdWidth-1:0] id_d, id_q;       // Id of the request, must be same for the response

  logic req1_d, req1_q;                          // Request valid
  logic we1_d, we1_q;                            // Write enable
  logic [ObiCfg.AddrWidth-1:0] addr1_d, addr1_q; // Internal address of the word to read
  logic [ObiCfg.IdWidth-1:0] id1_d, id1_q;       // Id of the request, must be same for the response


  // Signals used to create the response
  logic [ObiCfg.DataWidth-1:0] rsp_data; // Data field of the obi response
  logic rsp_err;                         // Error field of the obi response

  // Wire the registers holding the request
  // TODO 1: Modify the code such that the ROM will respond after 2 cycles instead of 1
  // Hint: You might want to add some additional registers to hold the request fields for 2 cycles instead of 1
  assign req1_d  = obi_req_i.req;
  assign id1_d   = obi_req_i.a.aid;
  assign we1_d   = obi_req_i.a.we;
  assign addr1_d = obi_req_i.a.addr;

  assign req_d = req1_q;
  assign id_d = id1_q;
  assign we_d = we1_q;
  assign addr_d = addr1_q;

  // Flip-flops
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      req_q  <= '0;
      id_q   <= '0;
      we_q   <= '0;
      addr_q <= '0;
      req1_q  <= '0;
      id1_q   <= '0;
      we1_q   <= '0;
      addr1_q <= '0;
    end else begin
      req_q  <= req_d;
      id_q   <= id_d;
      we_q   <= we_d;
      addr_q <= addr_d;

      req1_q  <= req1_d;
      id1_q   <= id1_d;
      we1_q   <= we1_d;
      addr1_q <= addr1_d;
    end
  end

  // // Assign the OBI response data
  // TODO 2: Modify the code such that the ROM will contain (up to) 32 ASCII chars
  // hold in your initials in the form: "JD&JD's ASIC\0"
  logic [4:0] word_addr;
  always_comb begin
    rsp_data = '0;
    rsp_err  = '0;
    word_addr = addr_q[6:2];

    if(req_q) begin
      if(~we_q) begin
        case(word_addr)
          32'h0: rsp_data = 32'h02;
          32'h1: rsp_data = 32'h01;
          32'h2: rsp_data = 32'h03;
          32'h3: rsp_data = 32'h04;
          32'h4: rsp_data = 32'h05;
          32'h5: rsp_data = 32'h06;
          32'h6: rsp_data = 32'h07;
          32'h7: rsp_data = 32'h08;
          32'h8: rsp_data = 32'h01;
          32'h9: rsp_data = 32'h02;
          32'hA: rsp_data = 32'h03;
          32'hB: rsp_data = 32'h04;
          32'hC: rsp_data = 32'h05;
          32'hD: rsp_data = 32'h06;
          32'hE: rsp_data = 32'h07;
          32'hF: rsp_data = 32'h08;
          32'h10: rsp_data = 32'h08;
          default: rsp_data = 32'h0;
        endcase
      end else begin
        rsp_err = '1;
      end
    end
  end

  // Assign the OBI response signals
  // A channel
  assign obi_rsp_o.gnt = obi_req_i.req;
  // R channel
  assign obi_rsp_o.rvalid       = req_q;
  assign obi_rsp_o.r.rdata      = rsp_data;
  assign obi_rsp_o.r.rid        = id_q;
  assign obi_rsp_o.r.err        = rsp_err;
  assign obi_rsp_o.r.r_optional = '0;

endmodule
