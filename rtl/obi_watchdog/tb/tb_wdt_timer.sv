// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Self-checking unit testbench for wdt_timer.
// Build/run command is documented in tb/README (kept out of comments here
// so the "verilator" keyword is not mistaken for a lint pragma).

module tb_wdt_timer;

  logic        clk;
  logic        rst_n;
  logic        enable;
  logic        clear;
  logic [31:0] threshold;
  logic [31:0] count;
  logic        reached;

  int unsigned errors = 0;
  logic [31:0] held;

  // 100 MHz clock
  initial clk = 1'b0;
  always #5ns clk = ~clk;

  wdt_timer #(.WIDTH(32)) i_dut (
    .clk_i       ( clk       ),
    .rst_ni      ( rst_n     ),
    .enable_i    ( enable    ),
    .clear_i     ( clear     ),
    .threshold_i ( threshold ),
    .count_o     ( count     ),
    .reached_o   ( reached   )
  );

  // Helper: check with message
  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      $error("[FAIL] %s (count=%0d reached=%0b)", msg, count, reached);
      errors++;
    end else begin
      $display("[ OK ] %s", msg);
    end
  endtask

  initial begin
    // Init + reset
    enable    = 1'b0;
    clear     = 1'b0;
    threshold = 32'd5;
    rst_n     = 1'b0;
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    check(count == 0, "count is 0 after reset");
    check(reached == 0, "reached low after reset (disabled)");

    // Disabled: count must hold at 0
    repeat (3) @(negedge clk);
    check(count == 0, "count holds at 0 while disabled");

    // Enable: count should increment each cycle
    enable = 1'b1;
    @(negedge clk); // count was 0 -> 1
    check(count == 1, "count == 1 one cycle after enable");
    @(negedge clk);
    check(count == 2, "count == 2 two cycles after enable");

    // Run up to threshold (5). reached_o asserts combinationally when count>=5.
    // currently count==2; need 3 more increments to hit 5
    repeat (3) @(negedge clk);
    check(count == 5, "count reached threshold value 5");
    check(reached == 1, "reached asserted at count==threshold");

    // It stays asserted while count > threshold too
    @(negedge clk);
    check(count == 6, "count keeps counting past threshold");
    check(reached == 1, "reached stays high past threshold");

    // Clear has priority: count -> 0 next edge, even while enabled
    clear = 1'b1;
    @(negedge clk);
    check(count == 0, "clear forces count to 0 while enabled");
    check(reached == 0, "reached deasserts after clear");
    clear = 1'b0;

    // Resume counting from 0
    @(negedge clk);
    check(count == 1, "count resumes from 0 after clear released");

    // Disable mid-run: count holds
    enable = 1'b0;
    @(negedge clk);
    held = count;
    @(negedge clk);
    check(count == held, "count holds when disabled mid-run");

    // Summary
    if (errors == 0)
      $display("\n*** tb_wdt_timer: ALL CHECKS PASSED ***\n");
    else
      $display("\n*** tb_wdt_timer: %0d CHECK(S) FAILED ***\n", errors);
    $finish;
  end

endmodule
