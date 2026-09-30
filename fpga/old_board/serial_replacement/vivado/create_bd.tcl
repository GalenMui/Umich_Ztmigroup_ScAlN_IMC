# Smart ZYNQ SL V1.2 PS/AXI platform. The downstream AXI slave comes later.
create_bd_design platform

set ps [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
set_property -dict [list \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
] $ps

# The schematic confirms MT41K256M16TW-107 and x16 wiring. Vivado 2025.2
# lacks that exact part entry; RE-125 is a provisional, same-geometry preset.
# Board trace delays and actual DDR training remain to be verified.
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]

set axi [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:axi_interconnect:* axi_ic]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $axi
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins axi_ic/S00_AXI]
make_bd_intf_pins_external [get_bd_intf_pins axi_ic/M00_AXI]
set_property name FUTURE_AXI [get_bd_intf_ports M00_AXI_0]

set reset [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:* axi_reset]
set locked [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:xlconstant:* clock_locked]
set_property CONFIG.CONST_VAL {1} $locked

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins axi_ic/ACLK] \
    [get_bd_pins axi_ic/S00_ACLK] \
    [get_bd_pins axi_ic/M00_ACLK] \
    [get_bd_pins axi_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins axi_reset/ext_reset_in]
connect_bd_net [get_bd_pins clock_locked/dout] \
    [get_bd_pins axi_reset/dcm_locked]
connect_bd_net [get_bd_pins axi_reset/interconnect_aresetn] \
    [get_bd_pins axi_ic/ARESETN]
connect_bd_net [get_bd_pins axi_reset/peripheral_aresetn] \
    [get_bd_pins axi_ic/S00_ARESETN] \
    [get_bd_pins axi_ic/M00_ARESETN]

# Associate the external future-slave connection with this same clock/reset.
create_bd_port -dir O -type clk AXI_ACLK
connect_bd_net [get_bd_ports AXI_ACLK] [get_bd_pins ps7/FCLK_CLK0]
create_bd_port -dir O -type rst AXI_ARESETN
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports AXI_ARESETN]
connect_bd_net [get_bd_ports AXI_ARESETN] \
    [get_bd_pins axi_reset/peripheral_aresetn]
set_property -dict [list \
    CONFIG.ASSOCIATED_BUSIF {FUTURE_AXI} \
    CONFIG.ASSOCIATED_RESET {AXI_ARESETN} \
] [get_bd_ports AXI_ACLK]

# The external interface provides a provisional target segment. Its offset
# and range become the PS-visible reservation for the later AXI-Lite slave.
assign_bd_address
set mapped_seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps7/Data]]
if {[llength $mapped_seg] != 1} {
    error "Expected one future AXI address segment, found $mapped_seg"
}
set_property offset 0x43C00000 $mapped_seg
set_property range 64K $mapped_seg

validate_bd_design
save_bd_design
