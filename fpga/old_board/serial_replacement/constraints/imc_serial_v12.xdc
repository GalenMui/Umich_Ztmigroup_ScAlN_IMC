# Smart ZYNQ SL V1.2 IMC integration extras. J5 PACKAGE_PIN assignments
# live only in smart_zynq_sl_v12_j5.xdc (both files are active in Vivado).
# PS UART1 EMIO reaches the board's CH340 via Bank 34 PL pins.
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports UART_1_0_txd]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports UART_1_0_rxd]
# I2C SDA/SCL require external pull-ups to verified 3.3 V. The IOBUF only
# drives LOW or releases each line; no on-chip pull-up is assumed.
