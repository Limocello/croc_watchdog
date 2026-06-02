#Compile the hello world script
cd ../sw
make bin/helloworld.elf
riscv64-unknown-elf-objcopy -O verilog bin/helloworld.elf bin/helloworld.hex
riscv64-unknown-elf-objdump -D -s bin/helloworld.elf >bin/helloworld.dump
cd ../verilator/
./run_verilator.sh --run ../sw/bin/helloworld.hex