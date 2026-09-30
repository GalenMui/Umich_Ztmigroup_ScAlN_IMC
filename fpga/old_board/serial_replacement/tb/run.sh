#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

iverilog -g2012 -s imc_row_axi_tb -o "$build_dir/row.vvp" \
    "$root_dir"/rtl/*.sv "$root_dir"/tb/imc_row_axi_tb.sv
vvp "$build_dir/row.vvp"

iverilog -g2012 -s imc_serial_axi_tb -o "$build_dir/serial.vvp" \
    "$root_dir"/rtl/*.sv "$root_dir"/tb/ad5689_spi_monitor.sv \
    "$root_dir"/tb/ads1115_i2c_model.sv \
    "$root_dir"/tb/imc_serial_axi_tb.sv
vvp "$build_dir/serial.vvp"

python3 "$root_dir/tb/check_board_constraints.py"

# Reserved legacy registers are deliberately left present in the AXI map.
# The AXI register block uses synchronous reset while external outputs use
# asynchronous reset for immediate safe pin levels.
verilator --lint-only -Wall -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
    -Wno-UNUSEDPARAM -Wno-SYNCASYNCNET --top-module imc_top \
    "$root_dir"/rtl/*.sv
