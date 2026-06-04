// FILE COPIED FROM EXERCISE 1

// Copyright (c) 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

#include "uart.h"
#include "print.h"
#include "util.h"
#include "config.h"
#include "watchdog.h"


int main() {
    
    uart_init();
    printf("Hello World from Croc!\n");
    uart_write_flush();
    printf("watchdog state %u\n", watchdog_get_state());
    uart_write_flush();
    watchdog_set_thresholds(50000, 50000);
    watchdog_enable(1);
    printf("enabled");
    uart_write_flush();
    uint32_t i = 0;
    while(1){
        i++;
        if(i<20){
            watchdog_kick();
        }
        else{
            printf("paused watchdog \n");
            uart_write_flush();
        }
        printf("watchdog state %u\n", watchdog_get_state());
        uart_write_flush();

    }
    return 0;

    /*// setup the UART peripheral
    uart_init();

    // TODO: Print the User ROM content
    // 1. Define USER_ROM_BASE_ADDR in config.h
    // 2. Read eight 32-bit words from the ROM
    // 3. Print them using %x


    for(int i=0;i<16;i++){
        printf("%x \n",*reg32(USER_ROM_BASE_ADDR, i*4));
    } 

    // wait until uart has finished sending
    uart_write_flush();
    printf("Piss off!\n");
    uart_write_flush();
    return 0;*/
    
}
