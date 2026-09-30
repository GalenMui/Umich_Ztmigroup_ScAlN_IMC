// Vivado IP Integrator module-reference shim for the serial IMC core.
// It provides physical open-drain I2C pins around the SystemVerilog logic.
module smart_zynq_sl_v12_imc (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *)
    input wire s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aresetn, POLARITY ACTIVE_LOW" *)
    input wire s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
    input wire [7:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input wire [7:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input wire s_axi_rready,
    output wire sr_data,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sr_clk CLK",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME sr_clk, FREQ_HZ 10000000" *)
    output wire sr_clk,
    output wire sr_latch, sr_oe_n,
    output wire dac_sclk, dac_mosi, dac_cs_n, dac_reset_n,
    inout wire adc_scl, adc_sda,
    output wire ispp, vp, cc1, cc2, cc3,
    output wire integrator_reset1, integrator_reset2, integrator_reset3,
    output wire board_control, timing_pulse
);
    wire scl_drive_low, sda_drive_low, sda_sample;

    // I is tied LOW; T=1 releases the line. Neither pin is ever driven HIGH.
    IOBUF u_adc_scl_iobuf (
        .I(1'b0), .T(~scl_drive_low), .O(), .IO(adc_scl)
    );
    IOBUF u_adc_sda_iobuf (
        .I(1'b0), .T(~sda_drive_low), .O(sda_sample), .IO(adc_sda)
    );

    imc_top #(.CLK_HZ(100_000_000)) u_imc (
        .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .sr_data(sr_data), .sr_clk(sr_clk), .sr_latch(sr_latch),
        .sr_oe_n(sr_oe_n), .dac_sclk(dac_sclk), .dac_mosi(dac_mosi),
        .dac_cs_n(dac_cs_n), .dac_reset_n(dac_reset_n),
        .adc_scl_drive_low(scl_drive_low),
        .adc_sda_drive_low(sda_drive_low), .adc_sda_in(sda_sample),
        .ispp(ispp), .vp(vp), .cc1(cc1), .cc2(cc2), .cc3(cc3),
        .integrator_reset1(integrator_reset1),
        .integrator_reset2(integrator_reset2),
        .integrator_reset3(integrator_reset3),
        .board_control(board_control), .timing_pulse(timing_pulse)
    );
endmodule
