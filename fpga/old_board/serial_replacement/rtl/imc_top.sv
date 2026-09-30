// Row-only IMC AXI4-Lite control plane. Later peripheral commands are rejected.
module imc_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SHIFT_HZ = 10_000_000,
    parameter integer LATCH_US = 1
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *)
    input  logic        s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi_aresetn, POLARITY ACTIVE_LOW" *)
    input  logic        s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
    input  logic [7:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  logic        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output logic        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  logic [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  logic [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  logic        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output logic        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output logic [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output logic        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  logic        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  logic [7:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  logic        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output logic        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output logic [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output logic [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output logic        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  logic        s_axi_rready,
    output logic        sr_data,
    output logic        sr_clk,
    output logic        sr_latch,
    output logic        sr_oe_n
);
    localparam logic [7:0] CMD_SHIFT_ROWS = 8'h02;
    localparam logic [7:0] ERR_BUSY = 8'h01;
    localparam logic [7:0] ERR_COMMAND = 8'h02;
    localparam logic [7:0] ERR_ABORTED = 8'h03;

    logic start_pulse, clear_done_pulse, soft_reset_pulse, abort_pulse;
    logic [7:0] command;
    logic [15:0] row_mask;
    logic row_busy, row_done, row_initialized;
    logic row_active, done_sticky, error_sticky;
    logic [7:0] error_code;
    logic busy, accept_row, restart_safe;

    assign busy = row_active || row_busy || !row_initialized;
    assign restart_safe = soft_reset_pulse || abort_pulse;
    assign accept_row = start_pulse && !busy && command == CMD_SHIFT_ROWS &&
                        !restart_safe;

    row_shift_controller #(
        .CLK_HZ(CLK_HZ), .SHIFT_HZ(SHIFT_HZ), .LATCH_US(LATCH_US)
    ) u_rows (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn),
        .start(accept_row), .mask(row_mask), .restart_safe(restart_safe),
        .sr_data(sr_data), .sr_clk(sr_clk), .sr_latch(sr_latch),
        .sr_oe_n(sr_oe_n), .busy(row_busy), .done_pulse(row_done),
        .initialized(row_initialized)
    );

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            row_active   <= 1'b0;
            done_sticky  <= 1'b0;
            error_sticky <= 1'b0;
            error_code   <= 8'b0;
        end else if (restart_safe) begin
            row_active  <= 1'b0;
            done_sticky <= 1'b0;
            if (abort_pulse && row_active) begin
                error_sticky <= 1'b1;
                error_code   <= ERR_ABORTED;
            end else begin
                error_sticky <= 1'b0;
                error_code   <= 8'b0;
            end
        end else begin
            if (clear_done_pulse) done_sticky <= 1'b0;
            if (accept_row) begin
                row_active   <= 1'b1;
                done_sticky  <= 1'b0;
                error_sticky <= 1'b0;
                error_code   <= 8'b0;
            end else if (start_pulse) begin
                error_sticky <= 1'b1;
                error_code   <= busy ? ERR_BUSY : ERR_COMMAND;
            end
            if (row_active && row_done) begin
                row_active  <= 1'b0;
                done_sticky <= 1'b1;
            end
        end
    end

    control_regs u_control_regs (
        .s_axi_aclk, .s_axi_aresetn, .s_axi_awaddr, .s_axi_awvalid,
        .s_axi_awready, .s_axi_wdata, .s_axi_wstrb, .s_axi_wvalid,
        .s_axi_wready, .s_axi_bresp, .s_axi_bvalid, .s_axi_bready,
        .s_axi_araddr, .s_axi_arvalid, .s_axi_arready, .s_axi_rdata,
        .s_axi_rresp, .s_axi_rvalid, .s_axi_rready,
        .start_pulse, .clear_done_pulse, .soft_reset_pulse, .abort_pulse,
        .command, .row_mask,
        .row_index(), .column(), .ispp(), .vp(), .cc1(), .cc2(), .cc3(),
        .integrator_reset1(), .integrator_reset2(), .integrator_reset3(),
        .board_control(), .dac_a_code(), .dac_b_code(), .dac_channel(),
        .pulse_cycles(), .reset_pulse_cycles(), .t_unit_cycles(),
        .adc_channel(), .input_levels_0(), .input_levels_1(),
        .input_levels_2(), .use_offset(), .use_integrator(),
        .clear_switch_ctrl(restart_safe),
        .busy(busy), .done(done_sticky), .error(error_sticky),
        .adc_valid(1'b0), .initialized(row_initialized),
        .error_code(error_code), .adc_result(16'b0),
        .result_0(32'b0), .result_1(32'b0), .result_2(32'b0)
    );
endmodule
