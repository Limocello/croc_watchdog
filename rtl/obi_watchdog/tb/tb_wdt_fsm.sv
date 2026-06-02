// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Self-checking unit testbench for wdt_fsm.
// Exercises every transition: Idle -> Stage1 -> Stage2 -> Reset, the kick
// shortcuts, and the program_reset pulse width / cause-flag behaviour.

module tb_wdt_fsm;

  // Mirror the RTL state encoding for readability.
  localparam logic [1:0] IDLE   = 2'd0;
  localparam logic [1:0] STAGE1 = 2'd1;
  localparam logic [1:0] STAGE2 = 2'd2;
  localparam logic [1:0] RESET  = 2'd3;

  localparam int unsigned RESET_PULSE_CYCLES = 2;

  logic       clk;
  logic       rst_n;
  logic       enable;
  logic       kick;
  logic       reached;

  logic       stage2_sel;
  logic       clear_counter;
  logic       irq;
  logic       program_reset;
  logic       wdt_reset_set;
  logic       enable_clear;
  logic [1:0] state;

  int unsigned errors = 0;
  int unsigned prog_rst_cycles;

  initial clk = 1'b0;
  always #5ns clk = ~clk;

  wdt_fsm #(.RESET_PULSE_CYCLES(RESET_PULSE_CYCLES)) i_dut (
    .clk_i           ( clk           ),
    .rst_ni          ( rst_n         ),
    .enable_i        ( enable        ),
    .kick_i          ( kick          ),
    .reached_i       ( reached       ),
    .stage2_sel_o    ( stage2_sel    ),
    .clear_counter_o ( clear_counter ),
    .irq_o           ( irq           ),
    .program_reset_o ( program_reset ),
    .wdt_reset_set_o ( wdt_reset_set ),
    .enable_clear_o  ( enable_clear  ),
    .state_o         ( state         )
  );

  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      $error("[FAIL] %s (state=%0d irq=%0b prog_rst=%0b sel=%0b)",
             msg, state, irq, program_reset, stage2_sel);
      errors++;
    end else begin
      $display("[ OK ] %s", msg);
    end
  endtask

  initial begin
    enable  = 1'b0;
    kick    = 1'b0;
    reached = 1'b0;
    rst_n   = 1'b0;
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    check(state == IDLE, "starts in Idle after reset");
    check(stage2_sel == 1'b0, "threshold mux selects THRESHOLD_1 in Idle");

    // Idle -> Stage1 on enable
    enable = 1'b1;
    @(negedge clk);
    check(state == STAGE1, "Idle -> Stage1 when enabled");

    // Kick in Stage1: stays in Stage1, clears the counter
    kick = 1'b1;
    @(posedge clk); #1;
    check(clear_counter == 1'b1, "kick in Stage1 pulses clear_counter");
    @(negedge clk);
    kick = 1'b0;
    check(state == STAGE1, "kick keeps us in Stage1");

    // reached in Stage1 -> Stage2, with irq + clear on the transition
    reached = 1'b1;
    @(negedge clk);  // FSM commits Stage1 -> Stage2 on this edge
    reached = 1'b0;
    check(state == STAGE2, "Stage1 -> Stage2 when threshold reached");
    check(stage2_sel == 1'b1, "threshold mux switches to THRESHOLD_2 in Stage2");
    check(irq == 1'b1, "irq asserted while in Stage2");

    // Kick in Stage2 -> back to Stage1 (and irq deasserts there)
    kick = 1'b1;
    @(negedge clk);
    kick = 1'b0;
    check(state == STAGE1, "kick in Stage2 returns to Stage1");
    check(irq == 1'b0, "irq deasserts back in Stage1");
    check(stage2_sel == 1'b0, "mux back to THRESHOLD_1 in Stage1");

    // Drive all the way through: Stage1 -> Stage2 -> Reset (no kick)
    reached = 1'b1;
    @(negedge clk);             // -> Stage2
    check(state == STAGE2, "back to Stage2 for the reset path");
    // keep reached high; Stage2 should now progress to Reset
    @(negedge clk);             // -> Reset
    check(state == RESET, "Stage2 -> Reset when not kicked");
    reached = 1'b0;

    // Count program_reset pulse width. program_reset is high during Reset.
    prog_rst_cycles = 0;
    while (state == RESET) begin
      if (program_reset) prog_rst_cycles++;
      @(negedge clk);
    end
    check(prog_rst_cycles == RESET_PULSE_CYCLES,
          $sformatf("program_reset asserted for %0d cycles", RESET_PULSE_CYCLES));

    // After Reset we must be back in Idle, and the FSM must have requested
    // setting the cause flag and clearing the enable on the way out.
    check(state == IDLE, "Reset -> Idle after the pulse");

    // wdt_reset_set / enable_clear are single-cycle pulses fired on the last
    // Reset cycle; we sampled them via a separate monitor below.
    check(saw_wdt_reset_set, "wdt_reset_set pulsed during Reset");
    check(saw_enable_clear,  "enable_clear pulsed during Reset");

    if (errors == 0)
      $display("\n*** tb_wdt_fsm: ALL CHECKS PASSED ***\n");
    else
      $display("\n*** tb_wdt_fsm: %0d CHECK(S) FAILED ***\n", errors);
    $finish;
  end

  // Sticky monitors for the single-cycle FSM pulses.
  logic saw_wdt_reset_set = 1'b0;
  logic saw_enable_clear  = 1'b0;
  always @(posedge clk) begin
    if (wdt_reset_set) saw_wdt_reset_set <= 1'b1;
    if (enable_clear)  saw_enable_clear  <= 1'b1;
  end

endmodule
