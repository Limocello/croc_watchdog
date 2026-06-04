// Copyright (c) 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "util.h"
#include "watchdog.h"
#include "clint.h"
#include "config.h"

// The watchdog counts hardware clock cycles, while busy_wait() below counts
// loop iterations (~12 cycles each on CVE2). The threshold is therefore set
// far above any petting interval so a kick always lands well inside the
// Stage1 window, while a deliberate long wait reliably overruns it.
#define WDT_THRESHOLD   20000u   // cycles per stage
#define PET_ITERS       4
#define PET_WAIT        150u     // ~1800 cycles  << threshold  -> safe petting
#define EXPIRE_WAIT     3000u    // ~36000 cycles >  threshold  -> forces expiry

static volatile int      stage1_irq_count = 0;
static volatile uint32_t last_irq_cause   = 0;
static volatile int      isr_should_kick  = 1;  // 1 = recover, 0 = ack only

// Stage-1 ISR. Properly servicing the Stage-1 interrupt means *acknowledging*
// it (watchdog_ack) so irq_o deasserts and we don't immediately re-enter --
// CVE2 fast IRQs are level-sensitive, so without the ack a non-kicking ISR
// would re-trap until reset. Whether we also kick (recover) is controlled by
// isr_should_kick so the test can exercise both behaviours.
void croc_interrupt_handler(uint32_t cause) {
    last_irq_cause = cause;
    switch (cause) {
        case IRQ_WATCHDOG:
            stage1_irq_count++;
            watchdog_ack();                       // clear the IRQ (Stage2 -> Stage2_cleared)
            if (isr_should_kick) watchdog_kick(); // optionally recover (-> Stage1)
            break;
        default:
            set_interrupt_enable(0, cause);
            break;
    }
}

static void busy_wait(uint32_t iters) {
    for (volatile uint32_t i = 0; i < iters; i++) {
        asm volatile ("nop");
    }
}

int main(void) {
    // ----------------------------------------------------------------
    // Step 0: reset-cause readback after a watchdog reset.
    // The watchdog peripheral is NEVER reset by program_reset, so
    // STATUS.wdt_reset survives the core reset. If we got here because
    // the watchdog reset us (Step 5 below), report SUCCESS.
    // ----------------------------------------------------------------
    if (watchdog_get_reset_cause()) {
        watchdog_clear_reset_cause();
        CHECK_ASSERT(20, watchdog_get_reset_cause() == 0); // W1C worked
        return 0;                                          // SUCCESS
    }

    // ----------------------------------------------------------------
    // Step 1: register readback and initial state.
    // ----------------------------------------------------------------
    watchdog_enable(0);
    CHECK_ASSERT(1, watchdog_is_enabled() == 0);
    CHECK_ASSERT(2, watchdog_get_reset_cause() == 0);
    CHECK_ASSERT(3, watchdog_get_state() == WATCHDOG_STATE_IDLE);

    watchdog_set_thresholds(WDT_THRESHOLD, WDT_THRESHOLD);
    CHECK_ASSERT(4,
        *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_THRESHOLD_1_OFFSET) == WDT_THRESHOLD);
    CHECK_ASSERT(5,
        *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_THRESHOLD_2_OFFSET) == WDT_THRESHOLD);

    // ----------------------------------------------------------------
    // Step 2: normal petting -- kick before Stage1 can expire, repeatedly.
    // The IRQ must never fire and we must stay in Stage1.
    // ----------------------------------------------------------------
    set_interrupt_enable(1, IRQ_WATCHDOG);
    set_global_irq_enable(1);

    watchdog_enable(1);
    CHECK_ASSERT(6, watchdog_is_enabled() == 1);

    stage1_irq_count = 0;
    for (int i = 0; i < PET_ITERS; i++) {
        busy_wait(PET_WAIT);
        watchdog_kick();
    }
    CHECK_ASSERT(7, stage1_irq_count == 0);
    CHECK_ASSERT(8, watchdog_get_state() == WATCHDOG_STATE_STAGE1);

    // ----------------------------------------------------------------
    // Step 3: stop petting -> Stage1 IRQ fires. The ISR kicks, returning us
    // to Stage1, so even over a long wait we keep re-entering Stage1 and
    // never progress to Reset.
    // ----------------------------------------------------------------
    stage1_irq_count = 0;
    busy_wait(EXPIRE_WAIT);
    CHECK_ASSERT(9, stage1_irq_count >= 1);
    CHECK_ASSERT(10, last_irq_cause == IRQ_WATCHDOG);
    CHECK_ASSERT(11, watchdog_get_state() != WATCHDOG_STATE_RESET);
    CHECK_ASSERT(12, watchdog_get_reset_cause() == 0);

    // ----------------------------------------------------------------
    // Step 3b: interrupt servicing via ACK (no kick). The ISR now acknowledges
    // the Stage-1 IRQ (watchdog_ack -> Stage2_cleared, irq_o low) and returns
    // WITHOUT kicking. This proves the ISR runs a BOUNDED number of times
    // (exactly once) rather than re-entering forever on the level-sensitive
    // line -- the whole point of the ack. We poll for Stage2_cleared, then kick
    // to recover before the Stage-2 reset deadline.
    // ----------------------------------------------------------------
    isr_should_kick = 0;          // ISR will ack only, not kick
    watchdog_kick();              // fresh Stage1
    stage1_irq_count = 0;
    int got_cleared = 0;
    for (uint32_t g = 0; g < 100000u; g++) {
        if (stage1_irq_count >= 1 &&
            watchdog_get_state() == WATCHDOG_STATE_STAGE2_CLEARED) {
            got_cleared = 1;
            break;
        }
    }
    int ack_irqs = stage1_irq_count;
    watchdog_kick();              // recover before the Stage-2 reset deadline
    CHECK_ASSERT(16, got_cleared == 1);   // ack moved the FSM to Stage2_cleared
    CHECK_ASSERT(17, ack_irqs == 1);      // ISR fired exactly once (bounded re-entry)
    CHECK_ASSERT(18, watchdog_get_state() == WATCHDOG_STATE_STAGE1); // kick recovered
    isr_should_kick = 1;          // restore recover-on-IRQ behaviour

    // ----------------------------------------------------------------
    // Step 4: deactivate mid-run -> FSM returns to Idle, no further IRQs.
    // ----------------------------------------------------------------
    watchdog_enable(0);
    set_interrupt_enable(0, IRQ_WATCHDOG);
    stage1_irq_count = 0;
    busy_wait(PET_WAIT);
    CHECK_ASSERT(13, stage1_irq_count == 0);
    CHECK_ASSERT(14, watchdog_is_enabled() == 0);
    CHECK_ASSERT(15, watchdog_get_state() == WATCHDOG_STATE_IDLE);

    // ----------------------------------------------------------------
    // Step 5: full two-stage reset. With the ISR disabled the dog runs
    // through Stage1 and Stage2 unpetted, program_reset fires, and the
    // core reboots.
    //
    // The bootrom boots by enabling MSIE and executing WFI, waiting for a
    // CLINT msip. program_reset resets ONLY the core, not the CLINT, so we
    // pre-arm msip here; the rebooted bootrom's WFI then falls through
    // immediately and re-enters main(), which returns SUCCESS at Step 0.
    // ----------------------------------------------------------------
    set_interrupt_enable(0, IRQ_WATCHDOG);
    set_global_irq_enable(0);

    *reg32(CLINT_BASE_ADDR, CLINT_MSIP_REG_OFFSET) = 1; // pre-arm reboot wake

    watchdog_set_thresholds(WDT_THRESHOLD, WDT_THRESHOLD);
    watchdog_enable(1);

    // Spin well past Stage1 + Stage2; program_reset will yank us before this
    // completes.
    busy_wait(8 * EXPIRE_WAIT);

    // Reaching here means the watchdog never reset us.
    return 99;
}
