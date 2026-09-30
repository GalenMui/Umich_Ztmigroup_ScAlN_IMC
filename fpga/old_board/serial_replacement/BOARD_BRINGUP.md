# Smart ZYNQ SL V1.2 board bring-up

## Board and source status

- Board: HELLOFPGA Smart ZYNQ SL, hardware V1.2; device
  `XC7Z020-2CLG484I`, Vivado part `xc7z020clg484-2`.
- PS reference clock: 33.333 MHz. Separate PL oscillator: 50 MHz on M19.
- PS DDR: one Micron `MT41K256M16TW-107`, 4 Gb ×16 = 512 MB.
- JTAG is the first loading path. The board also has W25Q128JV QSPI and TF/SD,
  but persistent boot is outside this bring-up.
- J5 is Bank 35 at fixed 3.3 V. J6 is Bank 33 at VADJ, reportedly 3.3 V by
  default; it is unused here. The V1.2/V1.3/V1.3B J5 mapping supplied for
  this project is used; the older V1.0/V1.1 mapping is not.
- `fpga_zynq_board.opj.pdf` is the board source. Its V1.2/V1.3/V1.3B J5
  section confirms the package map and shows J5 GPIOs on physical header
  pins 7..40. The DDR sheet confirms the fitted part and 1.5 V DDR supply.

## Clock, PS, and AXI architecture

The integrated design uses **one 100 MHz PS FCLK0** for AXI4-Lite,
`imc_top`, and every serial engine. `FCLK_RESET0_N` feeds `proc_sys_reset`,
whose peripheral reset feeds the IMC block. There is no AXI/engine CDC. The
50 MHz M19 oscillator is not used by this serial-replacement project.

The Zynq7 PS enables `M_AXI_GP0` and UART1 on EMIO. UART1 goes to the board's
CH340 PL UART pins, TX L17 and RX M17. The AXI path is
`PS M_AXI_GP0 → AXI Interconnect → smart_zynq_sl_v12_imc S_AXI`, with the
IMC slave at **`0x43C0_0000`, 64 KiB range**. The address is assigned in the
Vivado Tcl; standalone C uses a generated `xparameters.h` macro via
`sw/imc_platform.h`. `DESIGN_ID` is at offset `0xFC` and should read
`0x0001_0001`.

Vivado 2025.2 does not list the exact `MT41K256M16TW-107` as a PS DDR part.
The Tcl selects its `MT41K256M16 RE-125` entry for the matching 4 Gb ×16
geometry at 533.333 MHz (1066 MT/s). This is a **bring-up candidate**; it is
not proof of DDR training or exact board trace timing. A DDR memory test is
required before linking the PS application into DDR. No ZedBoard/PYNQ preset
is applied. The PS MIO remains at its tool default unless required for JTAG;
QSPI/SD boot is not enabled. Verify all PS details against the V1.2 PDF and
actual board.

## Selected J5 allocation

All selected ports use `LVCMOS33`. Physical header pin number is J5 logical
index + 7, as shown by the V1.2 connector sheet. Pins 1/2 are 5 V, 3/4 are
3.3 V, and pins 5/6 are not part of the 34 GPIO allocation. No J6 pin is used.

| RTL/top port | J5 GPIO | Header pin | Package | Direction | Reset/idle | Teensy-controlled destination |
|---|---:|---:|---|---|---|---|
| `sr_data` | 0 | 7 | H19 | out | HIGH during safe init | 595 SER |
| `sr_clk` | 1 | 8 | H20 | out | LOW | 595 SHCP |
| `sr_latch` | 2 | 9 | E18 | out | LOW | 595 STCP |
| `sr_oe_n` | 3 | 10 | F18 | out | HIGH until `0xFFFF` latched | 595 OE# |
| `dac_mosi` | 4 | 11 | F17 | out | LOW | AD5689 DIN |
| `dac_sclk` | 5 | 12 | G17 | out | LOW | AD5689 SCLK |
| `dac_cs_n` | 6 | 13 | C17 | out | HIGH | AD5689 SYNC# |
| `dac_reset_n` | 7 | 14 | C18 | out | HIGH | AD5689 RESET# |
| `adc_scl` | 8 | 15 | G19 | open drain | released | ADS1115 SCL |
| `adc_sda` | 9 | 16 | F19 | open drain | released | ADS1115 SDA |
| `ispp` | 10 | 17 | E20 | out | LOW | ISPP routing input |
| `vp` | 11 | 18 | E19 | out | LOW | VP routing input |
| `cc1` | 12 | 19 | D22 | out | LOW | column 1 route |
| `cc2` | 13 | 20 | C22 | out | LOW | column 2 route |
| `cc3` | 14 | 21 | B22 | out | LOW | column 3 route |
| `integrator_reset1` | 15 | 22 | B21 | out | LOW | RESET1 logical level |
| `integrator_reset2` | 16 | 23 | B17 | out | LOW | RESET2 logical level |
| `integrator_reset3` | 17 | 24 | B16 | out | LOW | RESET3 logical level |
| `board_control` | 18 | 25 | A17 | out | LOW | reserved PU destination, wiring unconfirmed |
| `timing_pulse` | 19 | 26 | A16 | out | LOW | optional timing probe |

`IOBUF` instances connect both I²C pins. Their `I` inputs are tied LOW and
their tri-state inputs release the lines whenever the controllers do not
request a LOW. The FPGA never actively drives I²C HIGH. The active ADS1115
bus must have pull-ups to a voltage compatible with Bank 35; confirm their
presence and value before connecting J5. Do not tie a 5 V pull-up to J5.

## Files and build flow

- `vivado/create_project.tcl` and `vivado/create_bd.tcl`: create the PS,
  interconnect, reset, module-reference IMC wrapper, J5 ports, and AXI address.
- `vivado/build_bitstream.tcl`: synthesizes, implements, writes the bitstream,
  and exports the XSA.
- `board/smart_zynq_sl_v12_imc.v`: connects the integrated `imc_top.sv` and
  adds physical I²C `IOBUF` instances.
- `constraints/smart_zynq_sl_v12_j5.xdc`: authoritative V1.2 J5 index-to-pin
  list and each selected IMC port's sole PACKAGE_PIN assignment.
  `constraints/imc_serial_v12.xdc` constrains UART1 EMIO pins.
- `sw/imc_serial.[ch]`, `sw/imc_platform.h`, `sw/serial_bringup.c`: standalone
  PS API and first digital smoke application.

From the repository root, using Vivado 2025.2:

```sh
vivado -mode batch -source fpga/old_board/serial_replacement/vivado/create_project.tcl -tclargs /tmp/imc_v12_build
vivado -mode batch -source fpga/old_board/serial_replacement/vivado/build_bitstream.tcl -tclargs /tmp/imc_v12_build
```

The generated bitstream is under
`/tmp/imc_v12_build/imc_serial_v12/imc_serial_v12.runs/impl_1/system_wrapper.bit`;
the exported hardware platform is `/tmp/imc_v12_build/imc_serial_v12.xsa`.
The output directory can be changed with `-tclargs`. Keep these generated
files outside source control.

Import the generated `.xsa` into a **standalone** Vitis platform for the
Cortex-A9, inspect `xparameters.h` for the generated IMC base symbol, build
`sw/imc_serial.c` with `sw/serial_bringup.c`, and load the bitstream and ELF
over JTAG. No PYNQ, SD, QSPI, or hardcoded application address is required.
The application is intended to start in OCM until the board's DDR has passed
a memory test. Vitis must supply `xil_io.h`, `xil_printf.h`, and the generated
`xparameters.h`.

## Local build evidence and limits

Vivado 2025.2 validated the block design, synthesized, implemented, and wrote
both the integrated bitstream and XSA. The routed 100 MHz internal setup
slack was +4.177 ns and hold slack was +0.053 ns; bitstream DRC reported zero
errors. This check used the integrated project under `vivado/`.
The AXI row and serial peripheral integration simulations, board pin-map
check, Verilator lint, and host-side C syntax check passed. These checks do
not establish physical J5 levels, external serial timing, analog safety,
DDR training, or an operating Zynq PS application. No standalone ELF was
produced by these checks.

## First physical test sequence

1. Power V1.2; identify the XC7Z020 on JTAG. Confirm supply and Bank 35
   voltage before any IMC connection.
2. Program the integrated image over JTAG; check the 100 MHz FCLK with a
   Vivado hardware probe if clock verification is needed.
3. Load a small standalone ELF linked into OCM over JTAG. Test DDR training
   and memory before linking the full IMC application into DDR; confirm
   UART1 EMIO console through CH340 if enabled.
4. Read `DESIGN_ID`, wait for initialized, read/write safe AXI staging
   registers. Keep the IMC analog board disconnected.
5. Probe every selected J5 header pin at a slow safe test rate; confirm the
   package/header map, idle levels, and approximately 3.3 V output highs.
   Do not infer a pin from its table entry without probing it.
6. Connect only the 595 digital interface. On reset expect OE# HIGH, 16
   10 MHz rising SHCP edges shifting `0xFFFF` MSB first, then STCP HIGH for
   about 1 µs, then OE# LOW. Try `0xFFFF`, `0xFFFE`, `0xFFFD`, `0xF7FF` and
   check RC1, RC2, RC12 at the *latched* outputs.
7. Connect AD5689 digital pins. Expect SCLK idle LOW, one 24-bit MSB-first
   mode-1 frame per CS# assertion, and startup frames `60_0000`, `70_0000`,
   `31_0000`, `38_0000`. At 100 MHz FCLK, requested 30 MHz divides to an
   actual 25 MHz SPI clock. Start with zero codes; verify reference/gain and
   analog output scaling before nonzero codes.
8. Check ISPP, VP, CC1..3 and RESET1..3 one at a time on the disconnected
   digital nets. Verify the simultaneous 1 ms logical RESET pulse and the
   actual switch polarity before any device-array connection.
9. Verify ADS1115 pull-ups and bus voltage, then connect SCL/SDA. Run
   `imc_adc_probe()` and check address `0x48` ACK. Read known input levels on
   channels 1..3; check signed raw counts and software volts conversion.
10. Reproduce one known low-energy Teensy measurement sequence. Keep memory
    write/program pulses disabled until the measured digital and analog
    behavior agrees with the active Teensy procedure.

PS software retains voltage/code conversion, calibration, conductance math,
ISPP control loops, read/write experiment ordering, inference scheduling, and
host communication. PL supplies AXI registers, row serialization, DAC SPI,
ADS1115 I²C, named routing levels, and timed pulses. The future parallel
implementation remains separate.
