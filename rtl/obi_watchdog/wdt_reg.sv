// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// OBI subordinate register file for the two-stage watchdog.
//
// Register map (offsets, 32-bit accesses):
//   0x00  KICK         W    write-any-value to pet the dog (feed pulse)
//   0x04  CTRL         R/W  bit0 = enable, bit1 = write-once lock
//   0x08  THRESHOLD_1  R/W  first-stage threshold
//   0x0C  THRESHOLD_2  R/W  second-stage threshold
//   0x10  STATUS       R/W  [1:0] FSM state (RO), bit2 = wdt_reset (W1C)
//
// CTRL.lock is write-once: once set to 1 it cannot be cleared and CTRL,
// THRESHOLD_1 and THRESHOLD_2 become read-only. KICK and STATUS.wdt_reset
// stay writable through the lock so software can keep petting and clear
// the cause flag even after locking.
//
// The two thresholds are muxed by stage2_sel_i into threshold_o so the
// counter sees the active threshold. kick_pulse_o is a one-cycle pulse to
// the FSM whenever software writes the KICK register.

module wdt_reg #(
  parameter type obi_req_t = logic,
  parameter type obi_rsp_t = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,

  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o,

  // To FSM / timer
  output logic        enable_o,
  output logic        kick_pulse_o,
  output logic [31:0] threshold_o,

  // Mux/control inputs from the FSM
  input  logic        stage2_sel_i,
  input  logic [1:0]  state_i,
  input  logic        wdt_reset_set_i,
  input  logic        enable_clear_i
);

  // Register offsets
  localparam logic [4:0] WDT_KICK_OFFSET        = 5'h00;
  localparam logic [4:0] WDT_CTRL_OFFSET        = 5'h04;
  localparam logic [4:0] WDT_THRESHOLD_1_OFFSET = 5'h08;
  localparam logic [4:0] WDT_THRESHOLD_2_OFFSET = 5'h0C;
  localparam logic [4:0] WDT_STATUS_OFFSET      = 5'h10;

  // Internal address width (5 bits is enough for the offsets above).
  localparam int unsigned IntAddrWidth = 5;

  // Architectural state
  logic         enable_d,      enable_q;
  logic         lock_d,        lock_q;
  logic [31:0]  thr1_d,        thr1_q;
  logic [31:0]  thr2_d,        thr2_q;
  logic         wdt_reset_d,   wdt_reset_q;

  // OBI handshake registers (one-cycle response, matching obi_timer)
  obi_req_t    obi_req_d, obi_req_q;
  logic        err_d,     err_q;
  logic [31:0] rdata_d,   rdata_q;

  // Byte-enable mask -- used to support partial writes
  logic [31:0] be_mask;
  for (genvar i = 0; unsigned'(i) < 32/8; ++i) begin : gen_be_mask
    assign be_mask[8*i +: 8] = {8{obi_req_i.a.be[i]}};
  end

  assign obi_req_d = obi_req_i;

  // KICK is a fire-and-forget register: any write produces a one-cycle pulse.
  logic kick_pulse;
  assign kick_pulse_o = kick_pulse;

  // 2:1 threshold mux -- which threshold the FSM/timer is currently watching.
  assign threshold_o = stage2_sel_i ? thr2_q : thr1_q;
  assign enable_o    = enable_q;

  // OBI response
  always_comb begin : obi_response
    obi_rsp_o         = '0;
    obi_rsp_o.gnt     = 1'b1;
    obi_rsp_o.rvalid  = obi_req_q.req;
    obi_rsp_o.r.err   = err_q;
    obi_rsp_o.r.rid   = obi_req_q.a.aid;
    obi_rsp_o.r.rdata = rdata_q;
  end

  // Main read/write decode
  always_comb begin
    enable_d    = enable_q;
    lock_d      = lock_q;
    thr1_d      = thr1_q;
    thr2_d      = thr2_q;
    wdt_reset_d = wdt_reset_q;

    err_d      = 1'b0;
    rdata_d    = '0;
    kick_pulse = 1'b0;

    if (obi_req_i.req) begin
      if (obi_req_i.a.we) begin : write
        unique case ({obi_req_i.a.addr[IntAddrWidth-1:2], 2'b00})
          WDT_KICK_OFFSET: begin
            // Pulse out to the FSM. Value written is ignored.
            kick_pulse = 1'b1;
          end
          WDT_CTRL_OFFSET: begin
            // CTRL is read-only while locked.
            if (!lock_q) begin
              enable_d = (enable_q & ~be_mask[0]) |
                         (obi_req_i.a.wdata[0] & be_mask[0]);
              // Lock is write-once -- can be set but not cleared.
              if (obi_req_i.a.wdata[1] & be_mask[1]) begin
                lock_d = 1'b1;
              end
            end
          end
          WDT_THRESHOLD_1_OFFSET: begin
            if (!lock_q) begin
              thr1_d = (thr1_q & ~be_mask) | (obi_req_i.a.wdata & be_mask);
            end
          end
          WDT_THRESHOLD_2_OFFSET: begin
            if (!lock_q) begin
              thr2_d = (thr2_q & ~be_mask) | (obi_req_i.a.wdata & be_mask);
            end
          end
          WDT_STATUS_OFFSET: begin
            // Bit2 is W1C for the wdt_reset cause flag. Bits [1:0] are RO.
            if (obi_req_i.a.wdata[2] & be_mask[2]) begin
              wdt_reset_d = 1'b0;
            end
          end
          default: begin
            err_d = 1'b1;
          end
        endcase
      end else begin : read
        unique case ({obi_req_i.a.addr[IntAddrWidth-1:2], 2'b00})
          WDT_KICK_OFFSET: begin
            // KICK reads back as zero (write-only register).
            rdata_d = '0;
          end
          WDT_CTRL_OFFSET: begin
            rdata_d = {30'h0, lock_q, enable_q};
          end
          WDT_THRESHOLD_1_OFFSET: begin
            rdata_d = thr1_q;
          end
          WDT_THRESHOLD_2_OFFSET: begin
            rdata_d = thr2_q;
          end
          WDT_STATUS_OFFSET: begin
            rdata_d = {29'h0, wdt_reset_q, state_i};
          end
          default: begin
            rdata_d = 32'hBADCAB1E;
            err_d   = 1'b1;
          end
        endcase
      end
    end

    // FSM-driven side effects -- HW always wins over SW, so we apply these
    // last so a same-cycle SW write that races with the FSM cannot
    // accidentally suppress them.
    if (wdt_reset_set_i) wdt_reset_d = 1'b1;
    if (enable_clear_i)  enable_d    = 1'b0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      enable_q    <= 1'b0;
      lock_q      <= 1'b0;
      thr1_q      <= '0;
      thr2_q      <= '0;
      wdt_reset_q <= 1'b0;
      obi_req_q   <= '0;
      err_q       <= 1'b0;
      rdata_q     <= '0;
    end else begin
      enable_q    <= enable_d;
      lock_q      <= lock_d;
      thr1_q      <= thr1_d;
      thr2_q      <= thr2_d;
      wdt_reset_q <= wdt_reset_d;
      obi_req_q   <= obi_req_d;
      err_q       <= err_d;
      rdata_q     <= rdata_d;
    end
  end

endmodule
