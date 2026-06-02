// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Two-stage watchdog FSM.
//
//   Idle    : disabled. enable_i moves us to Stage1.
//   Stage1  : counter compared against THRESHOLD_1. A KICK restarts Stage1.
//             If reached_i fires before a kick we pulse irq_o, switch the
//             threshold mux to THRESHOLD_2 and clear the counter, then move
//             to Stage2.
//   Stage2  : counter compared against THRESHOLD_2. A KICK returns to Stage1.
//             If reached_i fires we move to Reset.
//   Reset   : pulses program_reset_o for RESET_PULSE_CYCLES cycles, raises
//             wdt_reset_o (latched in the register file), then returns to Idle
//             with the enable bit cleared.

module wdt_fsm #(
  parameter int unsigned RESET_PULSE_CYCLES = 2
) (
  input  logic clk_i,
  input  logic rst_ni,

  // Control from the register file
  input  logic enable_i,
  input  logic kick_i,
  input  logic reached_i,

  // Outputs to the register file / pads
  output logic       stage2_sel_o,       // 0 -> THRESHOLD_1, 1 -> THRESHOLD_2
  output logic       clear_counter_o,    // single-cycle pulse to clear wdt_timer
  output logic       irq_o,              // single-cycle pulse on Stage1->Stage2
  output logic       program_reset_o,    // multi-cycle pulse during Reset
  output logic       wdt_reset_set_o,    // latched STATUS.wdt_reset cause flag
  output logic       enable_clear_o,     // single-cycle pulse to clear CTRL.enable
  output logic [1:0] state_o             // for STATUS.state[1:0] readback
);

  // We need ceil(log2(RESET_PULSE_CYCLES)) bits to count the pulse width.
  // Use a small fixed counter; the synthesis tool will trim unused bits.
  localparam int unsigned RESET_CNT_WIDTH = (RESET_PULSE_CYCLES <= 1) ? 1 :
                                            $clog2(RESET_PULSE_CYCLES + 1);

  typedef enum logic [1:0] {
    Idle   = 2'd0,
    Stage1 = 2'd1,
    Stage2 = 2'd2,
    Reset  = 2'd3
  } state_e;

  state_e state_d, state_q;

  logic [RESET_CNT_WIDTH-1:0] rst_cnt_d, rst_cnt_q;

  // Next-state and reset-counter logic
  always_comb begin
    state_d   = state_q;
    rst_cnt_d = rst_cnt_q;

    unique case (state_q)
      Idle: begin
        rst_cnt_d = '0;
        if (enable_i) begin
          state_d = Stage1;
        end
      end

      Stage1: begin
        if (!enable_i) begin
          state_d = Idle;
        end else if (kick_i) begin
          state_d = Stage1;
        end else if (reached_i) begin
          state_d = Stage2;
        end
      end

      Stage2: begin
        if (!enable_i) begin
          state_d = Idle;
        end else if (kick_i) begin
          state_d = Stage1;
        end else if (reached_i) begin
          state_d   = Reset;
          rst_cnt_d = '0;
        end
      end

      Reset: begin
        if (rst_cnt_q == RESET_CNT_WIDTH'(RESET_PULSE_CYCLES - 1)) begin
          state_d   = Idle;
          rst_cnt_d = '0;
        end else begin
          rst_cnt_d = rst_cnt_q + 1;
        end
      end

      default: begin
        state_d   = Idle;
        rst_cnt_d = '0;
      end
    endcase
  end

  // Moore outputs (purely a function of state_q / transition into state_d)
  always_comb begin
    stage2_sel_o    = 1'b0;
    clear_counter_o = 1'b0;
    irq_o           = 1'b0;
    program_reset_o = 1'b0;
    wdt_reset_set_o = 1'b0;
    enable_clear_o  = 1'b0;
    state_o         = state_q;

    unique case (state_q)
      Idle: begin
        // Counter held cleared while disarmed so Stage1 starts fresh.
        clear_counter_o = 1'b1;
      end

      Stage1: begin
        // A kick in Stage1 restarts the counter.
        if (kick_i) begin
          clear_counter_o = 1'b1;
        end
      end

      Stage2: begin
        stage2_sel_o = 1'b1;
        // CVE2's mip is purely combinational (mip.irq_fast = irq_fast_i),
        // so we hold irq_o high the entire time we are in Stage2 to
        // guarantee the core sees it. The handler clears it implicitly by
        // kicking, which moves us back to Stage1.
        irq_o = 1'b1;
        // KICK from Stage2 goes back to Stage1; clear the counter for the
        // fresh Stage1 window. (The mux flips back combinationally once the
        // state register updates.)
        if (kick_i) begin
          clear_counter_o = 1'b1;
        end
      end

      Reset: begin
        program_reset_o = 1'b1;
        // On the last cycle of the reset pulse, latch the cause flag and
        // clear the enable so we end up disarmed in Idle.
        if (rst_cnt_q == RESET_CNT_WIDTH'(RESET_PULSE_CYCLES - 1)) begin
          wdt_reset_set_o = 1'b1;
          enable_clear_o  = 1'b1;
        end
      end

      default: begin
        // Defaults already cover this; explicit for clarity.
      end
    endcase

    // Stage1 -> Stage2 transition: clear the counter so Stage2's window
    // starts from zero (THRESHOLD_2 is now the active threshold). We do
    // not need to pulse irq_o here because it is held high throughout
    // Stage2 by the case above.
    if ((state_q == Stage1) && (state_d == Stage2)) begin
      clear_counter_o = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      state_q   <= Idle;
      rst_cnt_q <= '0;
    end else begin
      state_q   <= state_d;
      rst_cnt_q <= rst_cnt_d;
    end
  end

endmodule
