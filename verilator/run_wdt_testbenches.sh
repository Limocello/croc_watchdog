# Run the testbenches


cd ../rtl/obi_watchdog
verilator --binary -Wno-fatal -Wno-style --top-module tb_wdt_timer wdt_timer.sv tb/tb_wdt_timer.sv
./obj_dir/Vtb_wdt_timer 

verilator --binary --timing -Wno-fatal -Wno-style --top-module tb_wdt_fsm wdt_fsm.sv tb/tb_wdt_fsm.sv
./obj_dir/Vtb_wdt_fsm
