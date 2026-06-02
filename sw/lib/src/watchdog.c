// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "watchdog.h"
#include "util.h"
#include "config.h"

static inline uint32_t read_ctrl(void) {
    return *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_CTRL_OFFSET);
}

static inline void write_ctrl(uint32_t value) {
    *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_CTRL_OFFSET) = value;
}

static inline uint32_t read_status(void) {
    return *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_STATUS_OFFSET);
}

static inline void write_status(uint32_t value) {
    *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_STATUS_OFFSET) = value;
}

void watchdog_set_thresholds(uint32_t threshold_1, uint32_t threshold_2) {
    *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_THRESHOLD_1_OFFSET) = threshold_1;
    *reg32(WATCHDOG_BASE_ADDR, WATCHDOG_THRESHOLD_2_OFFSET) = threshold_2;
}

void watchdog_enable(int enable) {
    uint32_t ctrl = read_ctrl();
    if (enable) {
        ctrl |= (1u << WATCHDOG_CTRL_ENABLE_BIT);
    } else {
        ctrl &= ~(1u << WATCHDOG_CTRL_ENABLE_BIT);
    }
    write_ctrl(ctrl);
}

void watchdog_lock(void) {
    // Set both lock and current enable in one write so we don't accidentally
    // unset enable on the way in.
    uint32_t ctrl = read_ctrl();
    ctrl |= (1u << WATCHDOG_CTRL_LOCK_BIT);
    write_ctrl(ctrl);
}

int watchdog_get_reset_cause(void) {
    return (read_status() >> WATCHDOG_STATUS_RESET_BIT) & 0x1;
}

void watchdog_clear_reset_cause(void) {
    // STATUS.wdt_reset is write-one-to-clear.
    write_status(1u << WATCHDOG_STATUS_RESET_BIT);
}

int watchdog_is_enabled(void) {
    return (read_ctrl() >> WATCHDOG_CTRL_ENABLE_BIT) & 0x1;
}

uint32_t watchdog_get_state(void) {
    return read_status() & WATCHDOG_STATUS_STATE_MASK;
}
