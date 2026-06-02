// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Two-stage hardware watchdog as an OBI peripheral.
//
// Internally composed of three sub-modules:
//   wdt_reg   -- OBI subordinate register file and threshold mux
//   wdt_timer -- 32-bit count-up counter
//   wdt_fsm   -- Idle -> Stage1 -> Stage2 -> Reset state machine
//
// The watchdog is intentionally clocked only by rst_ni (the SoC reset);
// program_reset_o is fed back into the core's reset by the SoC, but the
// watchdog itself is NEVER reset by it. That guarantees STATUS.wdt_reset
// survives the reset of the core so software can read back why it came
// out of reset.

module obi_watchdog #(
  parameter int unsigned RESET_PULSE_CYCLES = 2,
  parameter type obi_req_t = logic,
  parameter type obi_rsp_t = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,

  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o,

  output logic     irq_o,
  output logic     program_reset_o
);

  // Register file <-> FSM/timer wires
  logic        enable;
  logic        kick_pulse;
  logic [31:0] threshold;

  // FSM <-> register file
  logic        stage2_sel;
  logic [1:0]  state;
  logic        wdt_reset_set;
  logic        enable_clear;

  // FSM <-> timer
  logic        clear_counter;
  logic        reached;

  wdt_reg #(
    .obi_req_t (obi_req_t),
    .obi_rsp_t (obi_rsp_t)
  ) i_wdt_reg (
    .clk_i,
    .rst_ni,
    .obi_req_i,
    .obi_rsp_o,

    .enable_o        ( enable        ),
    .kick_pulse_o    ( kick_pulse    ),
    .threshold_o     ( threshold     ),

    .stage2_sel_i    ( stage2_sel    ),
    .state_i         ( state         ),
    .wdt_reset_set_i ( wdt_reset_set ),
    .enable_clear_i  ( enable_clear  )
  );

  wdt_timer #(
    .WIDTH (32)
  ) i_wdt_timer (
    .clk_i,
    .rst_ni,
    .enable_i    ( enable        ),
    .clear_i     ( clear_counter ),
    .threshold_i ( threshold     ),
    .count_o     (),
    .reached_o   ( reached       )
  );

  wdt_fsm #(
    .RESET_PULSE_CYCLES (RESET_PULSE_CYCLES)
  ) i_wdt_fsm (
    .clk_i,
    .rst_ni,
    .enable_i        ( enable        ),
    .kick_i          ( kick_pulse    ),
    .reached_i       ( reached       ),

    .stage2_sel_o    ( stage2_sel    ),
    .clear_counter_o ( clear_counter ),
    .irq_o           ( irq_o         ),
    .program_reset_o ( program_reset_o ),
    .wdt_reset_set_o ( wdt_reset_set ),
    .enable_clear_o  ( enable_clear  ),
    .state_o         ( state         )
  );

endmodule
