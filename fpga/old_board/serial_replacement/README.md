# Serial replacement for the active Teensy experiment

The Smart ZYNQ SL V1.2 project, pin map, and JTAG sequence are in
[BOARD_BRINGUP.md](BOARD_BRINGUP.md).

This PL block implements the active `src/` Teensy peripheral transactions for a
Zynq-7000 PS running standalone C. It is not the later parallel experiment
architecture. The active ADC is the ADS1115 at I²C address `0x48`; the archived
AD7689 SPI path is not used here.

## Hierarchy and timing

`imc_top` owns one accepted command at a time and instantiates `control_regs`,
`row_shift_controller`, `ad5689_controller`, `ads1115_controller` (with
`i2c_byte_engine`), and three instances of `cycle_timer`. The PS may stage
register writes while an engine is active; every engine snapshots its inputs
when its command is accepted. A concurrent start is rejected with error `0x01`
and cannot interrupt the active operation. Abort and soft reset restart safe
initialization.

The reusable RTL's default `CLK_HZ` is a parameter assumption. The V1.2
Vivado project explicitly configures PS FCLK0 to 100 MHz; its physical rate
still needs board validation.
The row controller requires an integral half-period divider and defaults to
10 MHz at a 100 MHz control clock. The Teensy requests 30 MHz DAC SPI; a 100
MHz fabric clock cannot generate 30 MHz with equal integer half-periods, so
the default target of 30 MHz produces an actual 25 MHz SPI mode-1 waveform.
DAC and I²C dividers round up their half/quarter period counts, keeping the
actual bus rate at or below the target when the PL clock differs. ADS1115 I²C
targets 100 kHz. The I²C master uses open-drain drive-low /
release signals, with SDA sampled from the external resolved line. SCL clock
stretching is not implemented because no SCL input exists on this interface.

At reset, row OE# stays high until `0xFFFF` has been shifted and latched. The
DAC then receives `0x60_0000` (software reset), a 1 ms wait, `0x70_0000`
(reference enable), `0x31_0000` (A zero), and `0x38_0000` (B zero). DAC CS#
idles high, SCLK low, and the top-level DAC RESET# output remains high as in
the firmware. Routing and logical integrator reset levels start low. Global
`initialized` means these digital transactions completed; it does not mean an
ADS1115 or analog board is present. Neither DAC writes nor the ADC are
physically verified until hardware bring-up.

## AXI4-Lite contract

All offsets are 32-bit aligned; existing offsets remain in place. `CONTROL`
is write-one pulse control: bit 0 start, bit 1 clear sticky done, bit 2 soft
reset, bit 3 abort. Write `COMMAND`, write its input registers, then pulse
start. `STATUS` bit 0 busy, bit 1 sticky done, bit 2 sticky error, bit 3 ADC
valid, bit 4 initialized. `ERROR` contains the low-byte error code. An
accepted command clears prior done/error/ADC-valid; clear-done only clears
done. Aborting an active command records error `0x03`; an unsupported command
records `0x02`. ADS1115 NACK, timeout, and invalid channel are `0x10`, `0x11`,
and `0x12`. A successful ADC read places a signed 16-bit two's-complement
sample in `ADC_RESULT[15:0]`; `ADC_VALID` distinguishes a valid zero from an
error. `DESIGN_ID` remains `0x0001_0001` for compatibility with the row
bring-up program.

| Offset | Register | Implemented use |
|---:|---|---|
| `0x00` | CONTROL | command pulse / status clear / restart |
| `0x04` | STATUS | busy, done, error, ADC valid, initialized |
| `0x08` | COMMAND | command ID |
| `0x0C` | ERROR | error code |
| `0x10` | ROW_MASK | low 16 bits, shifted MSB first; `0xFFFF` deselects |
| `0x14`, `0x18` | ROW_INDEX, COLUMN | retained staging registers; unused by serial commands |
| `0x1C` | SWITCH_CTRL | staged ISPP bit 0, VP bit 1, CC1..3 bits 2..4, RESET1..3 bits 8..10, board-control bit 16 |
| `0x20`, `0x24` | DAC_A_CODE, DAC_B_CODE | raw 16-bit DAC codes |
| `0x28` | PULSE_CYCLES | cycle count for DELAY and `timing_pulse` |
| `0x2C` | T_UNIT_CYCLES | retained staging register; unused by serial commands |
| `0x30` | ADC_CHANNEL | one-based channels 1..4 map to AIN0..AIN3 |
| `0x34` | DAC_CHANNEL | 0=A/TOP_DRIVE, 1=B/BOT_DRIVE |
| `0x38` | RESET_PULSE_CYCLES | 0 means firmware-compatible 1 ms pulse; otherwise exact count |
| `0x40`, `0x44`, `0x48` | INPUT_LEVELS_0/1/2 | retained staging registers; unused by serial commands |
| `0x50` | FLAGS | retained staging register; unused by serial commands |
| `0x60` | ADC_RESULT | sign-extended by software from low 16 bits |
| `0x64`, `0x68`, `0x6C` | RESULT_0/1/2 | reserved read-only results; currently zero |
| `0xFC` | DESIGN_ID | compatibility ID |

Commands: `0x00` NOP (reserved), `0x01` SAFE_INIT, `0x02` SHIFT_ROWS, `0x03` DAC_WRITE, `0x04`
ADC_READ, `0x05` SET_SWITCHES, `0x06` INTEGRATOR_RESET, `0x07` DELAY,
`0x08` ADC_PROBE (config read without a conversion), `0x7F` SAFE_STATE.
SAFE_INIT and SAFE_STATE both clear routing, abort current
engines, and redo row/DAC startup. `0x10` READ_CELL, `0x11` WRITE_CELL, and
`0x20` RUN_INFERENCE remain reserved and are rejected. Existing ROW_INDEX,
COLUMN, T_UNIT_CYCLES, INPUT_LEVELS, FLAGS, and RESULT registers remain at
their original offsets but are not consumed by these low-level primitives.
For one row, the active Teensy uses `mask = ~(1 << (row - 1))`; mask bit 0
maps to RC1, bit 11 to RC12, and unused bits 12..15 should normally stay HIGH.

`SWITCH_CTRL` is a staging register; outputs update together only on
SET_SWITCHES. Teensy initializes ISPP/VP/CC LOW. HIGH ISPP routes TOP_DRIVE to
the row bus, HIGH VP routes BOT_DRIVE to the column SA path, and HIGH CCn
routes column n to TIA n; LOW CCn selects the SA path. RESET1..3 are logical
Teensy levels: HIGH during the reset helper, LOW for accumulation. The reset
command asserts all three for the programmed count and releases all LOW.
Physical switch polarity and board wiring still need measurement. The legacy
`board_control` output remains a staged bit. J5[18] is reserved for it, but
its physical destination is unresolved; leave that wire disconnected until
the active Teensy harness confirms the intended PU connection.

The ADS1115 controller sends config `C3E3`, `D3E3`, `E3E3`, or `F3E3` for
channels 1..4, polls the config OS bit at roughly 50 us intervals, stops after
roughly 10 ms, then reads the conversion register. It retries poll-read NACKs
until timeout as the firmware's `conversion_ready()` loop does. Normal voltage
conversion (`raw * 4.096 / 32767`) and DAC volts-to-code math remain in C.
`ADC_PROBE` reproduces the Teensy setup's config-register presence read and
returns that word through `ADC_RESULT`; a NACK returns `0x10`. PS software may
repeat the probe up to 20 times with 15 ms gaps as in `adc_init()`.
The active firmware uses separate DAC A/B writes and does not pulse LDAC.

## Software boundary and verification

`sw/imc_serial.h` and `.c` are a standalone MMIO API using `Xil_In32` and
`Xil_Out32`; pass the platform-generated AXI base into `imc_device_init`.
`sw/serial_bringup.c` is a digital-only smoke example. The PS still chooses
experiment sequences, voltages, masks, ISPP loops, calibration, inference
scheduling, and host communication. PL executes individual peripheral
transactions and deterministic timed pulses. A future scheduler can compose
the existing engine interfaces after this serial implementation is validated.

Run `bash tb/run.sh` from this directory or any other working directory. It
runs the AXI-driven 595 test, AXI integration test with independent SPI/I²C
models, then Verilator lint. The lint command suppresses unused legacy AXI
register warnings and the intentional mixed synchronous/asynchronous reset
style; other warnings fail lint. Simulation validates protocol timing and
register behavior, not the actual analog response or board electrical levels.

## Hardware-dependent work

The Smart ZYNQ SL V1.2 pin map, 100 MHz FCLK, and AXI base are defined in
[BOARD_BRINGUP.md](BOARD_BRINGUP.md). Physical J5-to-IMC wiring, DDR
operation, I/O bank levels, and pull-ups for the open-drain I²C signals
require measurement. Validate RESET#/LDAC/OE# electrical behavior on the
assembled board. Check the DAC
gain/reference strap and analog drive voltage scaling before commanding
nonzero codes. Measure the physical RESET and routing switch polarity before
connecting experimental devices. The firmware's 20 ms ADC-startup wait and
20-attempt presence probe stay in PS bring-up if required; PL global
initialization deliberately does not block on external I²C ACK.
