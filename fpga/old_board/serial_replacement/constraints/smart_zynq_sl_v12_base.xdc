# Smart ZYNQ SL V1.2 PL oscillator: 50 MHz on M19, LVCMOS33.
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports clk_50]
create_clock -name clk_50 -period 20.000 [get_ports clk_50]
