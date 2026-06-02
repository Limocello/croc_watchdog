// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// 32-bit count-up counter used by the watchdog.
// Counts up every clock cycle while enable_i is asserted.
// Synchronous clear_i (high-priority) drops the count to zero on the next edge.
// reached_o pulses combinationally when the count reaches threshold_i.

module wdt_timer #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             enable_i,
  input  logic             clear_i,
  input  logic [WIDTH-1:0] threshold_i,
  output logic [WIDTH-1:0] count_o,
  output logic             reached_o
);

  logic [WIDTH-1:0] count_d, count_q;

  always_comb begin
    count_d = count_q;
    if (clear_i) begin
      count_d = '0;
    end else if (enable_i) begin
      count_d = count_q + 1;
    end
  end

  assign count_o   = count_q;
  assign reached_o = enable_i && (count_q >= threshold_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      count_q <= '0;
    end else begin
      count_q <= count_d;
    end
  end

endmodule
