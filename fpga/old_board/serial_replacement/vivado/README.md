# Smart ZYNQ SL V1.2 serial-replacement Vivado flow

From the repository root, run Vivado 2025.2:

```sh
vivado -mode batch -source fpga/old_board/serial_replacement/vivado/create_project.tcl -tclargs /tmp/imc_v12_build
vivado -mode batch -source fpga/old_board/serial_replacement/vivado/build_bitstream.tcl -tclargs /tmp/imc_v12_build
```

The first script creates `imc_serial_v12` for `xc7z020clg484-2`, adds all
serial RTL and the `smart_zynq_sl_v12_imc` IOBUF wrapper, then sources
`create_bd.tcl`. The block design connects PS7 `M_AXI_GP0` through one AXI
Interconnect to the IMC AXI4-Lite slave at `0x43C00000` (64 KiB). The PS
33.333333 MHz reference setting generates a single 100 MHz FCLK0 for AXI,
the IMC core, and every peripheral engine. `proc_sys_reset` supplies their
reset. The separate 50 MHz M19 PL oscillator is unused by this design; there
is no clock-domain crossing.

DDR and FIXED_IO are externalized, and PS UART1 EMIO uses the board's CH340
pins. `smart_zynq_sl_v12_j5.xdc` assigns the IMC pins on Bank 35 at
LVCMOS33. `imc_serial_v12.xdc` assigns the UART pins. Both I²C lines pass
through IOBUFs that drive only LOW or release; external 3.3 V pull-ups are
required. See [BOARD_BRINGUP.md](../BOARD_BRINGUP.md) for the pin table.

The second script runs synthesis, implementation, and bitstream generation,
then writes `imc_serial_v12.xsa` in the output directory. All generated
files stay in that directory and outside source control.

The exact fitted DDR3 part `MT41K256M16TW-107` is absent from the local PS7
catalog. The Tcl selects the same-geometry `MT41K256M16 RE-125` preset at
533.333 MHz. DDR training and board trace timing still require physical
validation before software relies on DDR.
