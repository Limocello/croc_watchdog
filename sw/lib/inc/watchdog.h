// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <stdint.h>
#include "config.h"

// Register offsets
#define WATCHDOG_KICK_OFFSET          0x00
#define WATCHDOG_CTRL_OFFSET          0x04
#define WATCHDOG_THRESHOLD_1_OFFSET   0x08
#define WATCHDOG_THRESHOLD_2_OFFSET   0x0C
#define WATCHDOG_STATUS_OFFSET        0x10
#define WATCHDOG_IRPT_CLEAR_OFFSET    0x14

// CTRL bit positions
#define WATCHDOG_CTRL_ENABLE_BIT     0
#define WATCHDOG_CTRL_LOCK_BIT       1

// STATUS bit positions: [2:0] = FSM state (RO), bit3 = wdt_reset cause (W1C)
#define WATCHDOG_STATUS_STATE_MASK   0x7
#define WATCHDOG_STATUS_RESET_BIT    3

// FSM state encoding (matches RTL wdt_fsm state_e)
#define WATCHDOG_STATE_IDLE          0
#define WATCHDOG_STATE_STAGE1        1
#define WATCHDOG_STATE_STAGE2        2
#define WATCHDOG_STATE_STAGE2_CLEARED 3
#define WATCHDOG_STATE_RESET         4

// Configure both thresholds. Must be called before watchdog_enable().
void watchdog_set_thresholds(uint32_t threshold_1, uint32_t threshold_2);

// Enable / disable the watchdog. Ineffective once the lock bit is set.
void watchdog_enable(int enable);

// Set the write-once lock. After this returns, CTRL and THRESHOLD_* are RO.
void watchdog_lock(void);

// "Pet the dog" -- restart Stage1 from anywhere.
static inline void watchdog_kick(void) {
    // A single store to KICK is enough; the value is ignored.
    *(volatile uint32_t *)(WATCHDOG_BASE_ADDR + WATCHDOG_KICK_OFFSET) = 0;
}

// Acknowledge the Stage-1 interrupt: deasserts irq_o (Stage2 -> Stage2_cleared)
// so the ISR can return without re-entering. Does NOT restart the deadline --
// the watchdog keeps counting toward the Stage-2 reset unless you also kick.
// Call this from the watchdog ISR.
static inline void watchdog_ack(void) {
    *(volatile uint32_t *)(WATCHDOG_BASE_ADDR + WATCHDOG_IRPT_CLEAR_OFFSET) = 0;
}

// Returns 1 if the most recent boot was caused by a watchdog reset, else 0.
int watchdog_get_reset_cause(void);

// Clear the watchdog reset cause flag (W1C). No-op if not set.
void watchdog_clear_reset_cause(void);

// Read back CTRL.enable (debugging helper).
int watchdog_is_enabled(void);

// Read back the FSM state ([2:0] of STATUS). See WATCHDOG_STATE_* above.
uint32_t watchdog_get_state(void);
