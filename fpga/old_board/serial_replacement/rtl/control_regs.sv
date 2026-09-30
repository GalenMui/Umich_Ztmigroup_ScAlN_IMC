module control_regs (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [7:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [7:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    output logic        start_pulse,
    output logic        clear_done_pulse,
    output logic        soft_reset_pulse,
    output logic        abort_pulse,
    output logic [7:0]  command,
    output logic [15:0] row_mask,
    output logic [3:0]  row_index,
    output logic [1:0]  column,
    output logic        ispp,
    output logic        vp,
    output logic        cc1,
    output logic        cc2,
    output logic        cc3,
    output logic        integrator_reset1,
    output logic        integrator_reset2,
    output logic        integrator_reset3,
    output logic        board_control,
    output logic [15:0] dac_a_code,
    output logic [15:0] dac_b_code,
    output logic        dac_channel,
    output logic [31:0] pulse_cycles,
    output logic [31:0] reset_pulse_cycles,
    output logic [31:0] t_unit_cycles,
    output logic [2:0]  adc_channel,
    output logic [31:0] input_levels_0,
    output logic [31:0] input_levels_1,
    output logic [31:0] input_levels_2,
    output logic        use_offset,
    output logic        use_integrator,
    input  logic        clear_switch_ctrl,

    input  logic        busy,
    input  logic        done,
    input  logic        error,
    input  logic        adc_valid,
    input  logic        initialized,
    input  logic [7:0]  error_code,
    input  logic [15:0] adc_result,
    input  logic [31:0] result_0,
    input  logic [31:0] result_1,
    input  logic [31:0] result_2
);
    localparam logic [7:0] ADDR_CONTROL        = 8'h00;
    localparam logic [7:0] ADDR_STATUS         = 8'h04;
    localparam logic [7:0] ADDR_COMMAND        = 8'h08;
    localparam logic [7:0] ADDR_ERROR          = 8'h0C;
    localparam logic [7:0] ADDR_ROW_MASK       = 8'h10;
    localparam logic [7:0] ADDR_ROW_INDEX      = 8'h14;
    localparam logic [7:0] ADDR_COLUMN         = 8'h18;
    localparam logic [7:0] ADDR_SWITCH_CTRL    = 8'h1C;
    localparam logic [7:0] ADDR_DAC_A_CODE     = 8'h20;
    localparam logic [7:0] ADDR_DAC_B_CODE     = 8'h24;
    localparam logic [7:0] ADDR_PULSE_CYCLES   = 8'h28;
    localparam logic [7:0] ADDR_T_UNIT_CYCLES  = 8'h2C;
    localparam logic [7:0] ADDR_ADC_CHANNEL    = 8'h30;
    localparam logic [7:0] ADDR_DAC_CHANNEL    = 8'h34;
    localparam logic [7:0] ADDR_RESET_PULSE_CYCLES = 8'h38;
    localparam logic [7:0] ADDR_INPUT_LEVELS_0 = 8'h40;
    localparam logic [7:0] ADDR_INPUT_LEVELS_1 = 8'h44;
    localparam logic [7:0] ADDR_INPUT_LEVELS_2 = 8'h48;
    localparam logic [7:0] ADDR_FLAGS          = 8'h50;
    localparam logic [7:0] ADDR_ADC_RESULT     = 8'h60;
    localparam logic [7:0] ADDR_RESULT_0       = 8'h64;
    localparam logic [7:0] ADDR_RESULT_1       = 8'h68;
    localparam logic [7:0] ADDR_RESULT_2       = 8'h6C;
    localparam logic [7:0] ADDR_DESIGN_ID      = 8'hFC;

    localparam logic [7:0] CMD_NOP              = 8'h00;
    localparam logic [7:0] CMD_SAFE_INIT        = 8'h01;
    localparam logic [7:0] CMD_SHIFT_ROWS       = 8'h02;
    localparam logic [7:0] CMD_DAC_WRITE        = 8'h03;
    localparam logic [7:0] CMD_ADC_READ         = 8'h04;
    localparam logic [7:0] CMD_SET_SWITCHES     = 8'h05;
    localparam logic [7:0] CMD_INTEGRATOR_RESET = 8'h06;
    localparam logic [7:0] CMD_READ_CELL        = 8'h10;
    localparam logic [7:0] CMD_WRITE_CELL       = 8'h11;
    localparam logic [7:0] CMD_RUN_INFERENCE    = 8'h20;
    localparam logic [7:0] CMD_SAFE_STATE       = 8'h7F;

    localparam logic [31:0] DESIGN_ID = 32'h0001_0001;

    logic        aw_pending;
    logic [7:0]  awaddr_hold;
    logic        w_pending;
    logic [31:0] wdata_hold;
    logic [3:0]  wstrb_hold;
    logic        write_commit;
    logic [31:0] read_value;

    logic [31:0] command_reg;
    logic [31:0] row_mask_reg;
    logic [31:0] row_index_reg;
    logic [31:0] column_reg;
    logic [31:0] switch_ctrl_reg;
    logic [31:0] dac_a_code_reg;
    logic [31:0] dac_b_code_reg;
    logic [31:0] pulse_cycles_reg;
    logic [31:0] t_unit_cycles_reg;
    logic [31:0] adc_channel_reg;
    logic [31:0] dac_channel_reg;
    logic [31:0] reset_pulse_cycles_reg;
    logic [31:0] input_levels_0_reg;
    logic [31:0] input_levels_1_reg;
    logic [31:0] input_levels_2_reg;
    logic [31:0] flags_reg;

    function automatic logic [31:0] merge_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strobe
    );
        logic [31:0] merged;
        merged = old_value;
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
            if (strobe[byte_index])
                merged[8*byte_index +: 8] = new_value[8*byte_index +: 8];
        end
        return merged;
    endfunction

    // Address and data can arrive on different AXI cycles.
    assign s_axi_awready = !aw_pending && !s_axi_bvalid && !s_axi_rvalid;
    assign s_axi_wready  = !w_pending  && !s_axi_bvalid && !s_axi_rvalid;
    assign s_axi_arready = !aw_pending && !w_pending && !s_axi_bvalid &&
                           !s_axi_rvalid && !s_axi_awvalid && !s_axi_wvalid;
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;
    assign write_commit = aw_pending && w_pending && !s_axi_bvalid;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            aw_pending   <= 1'b0;
            awaddr_hold  <= 8'b0;
            w_pending    <= 1'b0;
            wdata_hold   <= 32'b0;
            wstrb_hold   <= 4'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_hold <= s_axi_awaddr;
                aw_pending  <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
                w_pending  <= 1'b1;
            end
            if (write_commit) begin
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rdata  <= read_value;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            start_pulse        <= 1'b0;
            clear_done_pulse   <= 1'b0;
            soft_reset_pulse   <= 1'b0;
            abort_pulse        <= 1'b0;
            command_reg        <= {24'b0, CMD_NOP};
            row_mask_reg       <= 32'h0000_FFFF; // 0 selects a row on the 595 chain
            row_index_reg      <= 32'b0;
            column_reg         <= 32'b0;
            switch_ctrl_reg    <= 32'b0;
            dac_a_code_reg     <= 32'b0;
            dac_b_code_reg     <= 32'b0;
            pulse_cycles_reg   <= 32'b0;
            t_unit_cycles_reg  <= 32'b0;
            adc_channel_reg    <= 32'b0;
            dac_channel_reg    <= 32'b0;
            reset_pulse_cycles_reg <= 32'b0;
            input_levels_0_reg <= 32'b0;
            input_levels_1_reg <= 32'b0;
            input_levels_2_reg <= 32'b0;
            flags_reg          <= 32'b0;
        end else begin
            start_pulse      <= 1'b0;
            clear_done_pulse <= 1'b0;
            soft_reset_pulse <= 1'b0;
            abort_pulse      <= 1'b0;
            if (clear_switch_ctrl)
                switch_ctrl_reg <= 32'b0;
            if (write_commit) begin
                case (awaddr_hold)
                    ADDR_CONTROL: if (wstrb_hold[0]) begin
                        start_pulse      <= wdata_hold[0];
                        clear_done_pulse <= wdata_hold[1];
                        soft_reset_pulse <= wdata_hold[2];
                        abort_pulse      <= wdata_hold[3];
                    end
                    ADDR_COMMAND: command_reg <= merge_wstrb(command_reg, wdata_hold, wstrb_hold) & 32'h0000_00FF;
                    ADDR_ROW_MASK: row_mask_reg <= merge_wstrb(row_mask_reg, wdata_hold, wstrb_hold) & 32'h0000_FFFF;
                    ADDR_ROW_INDEX: row_index_reg <= merge_wstrb(row_index_reg, wdata_hold, wstrb_hold) & 32'h0000_000F;
                    ADDR_COLUMN: column_reg <= merge_wstrb(column_reg, wdata_hold, wstrb_hold) & 32'h0000_0003;
                    ADDR_SWITCH_CTRL: if (!clear_switch_ctrl)
                        switch_ctrl_reg <= merge_wstrb(switch_ctrl_reg, wdata_hold, wstrb_hold) & 32'h0001_071F;
                    ADDR_DAC_A_CODE: dac_a_code_reg <= merge_wstrb(dac_a_code_reg, wdata_hold, wstrb_hold) & 32'h0000_FFFF;
                    ADDR_DAC_B_CODE: dac_b_code_reg <= merge_wstrb(dac_b_code_reg, wdata_hold, wstrb_hold) & 32'h0000_FFFF;
                    ADDR_PULSE_CYCLES: pulse_cycles_reg <= merge_wstrb(pulse_cycles_reg, wdata_hold, wstrb_hold);
                    ADDR_T_UNIT_CYCLES: t_unit_cycles_reg <= merge_wstrb(t_unit_cycles_reg, wdata_hold, wstrb_hold);
                    ADDR_ADC_CHANNEL: adc_channel_reg <= merge_wstrb(adc_channel_reg, wdata_hold, wstrb_hold) & 32'h0000_0007;
                    ADDR_DAC_CHANNEL: dac_channel_reg <= merge_wstrb(dac_channel_reg, wdata_hold, wstrb_hold) & 32'h0000_0001;
                    ADDR_RESET_PULSE_CYCLES: reset_pulse_cycles_reg <= merge_wstrb(reset_pulse_cycles_reg, wdata_hold, wstrb_hold);
                    ADDR_INPUT_LEVELS_0: input_levels_0_reg <= merge_wstrb(input_levels_0_reg, wdata_hold, wstrb_hold);
                    ADDR_INPUT_LEVELS_1: input_levels_1_reg <= merge_wstrb(input_levels_1_reg, wdata_hold, wstrb_hold);
                    ADDR_INPUT_LEVELS_2: input_levels_2_reg <= merge_wstrb(input_levels_2_reg, wdata_hold, wstrb_hold);
                    ADDR_FLAGS: flags_reg <= merge_wstrb(flags_reg, wdata_hold, wstrb_hold) & 32'h0000_0003;
                    default: ; // Read-only and unmapped addresses ignore writes.
                endcase
            end
        end
    end

    always_comb begin
        read_value = 32'b0;
        case (s_axi_araddr)
            ADDR_CONTROL:        read_value = 32'b0;
            ADDR_STATUS:         read_value = {27'b0, initialized, adc_valid, error, done, busy};
            ADDR_COMMAND:        read_value = command_reg;
            ADDR_ERROR:          read_value = {24'b0, error_code};
            ADDR_ROW_MASK:       read_value = row_mask_reg;
            ADDR_ROW_INDEX:      read_value = row_index_reg;
            ADDR_COLUMN:         read_value = column_reg;
            ADDR_SWITCH_CTRL:    read_value = switch_ctrl_reg;
            ADDR_DAC_A_CODE:     read_value = dac_a_code_reg;
            ADDR_DAC_B_CODE:     read_value = dac_b_code_reg;
            ADDR_PULSE_CYCLES:   read_value = pulse_cycles_reg;
            ADDR_T_UNIT_CYCLES:  read_value = t_unit_cycles_reg;
            ADDR_ADC_CHANNEL:    read_value = adc_channel_reg;
            ADDR_DAC_CHANNEL:    read_value = dac_channel_reg;
            ADDR_RESET_PULSE_CYCLES: read_value = reset_pulse_cycles_reg;
            ADDR_INPUT_LEVELS_0: read_value = input_levels_0_reg;
            ADDR_INPUT_LEVELS_1: read_value = input_levels_1_reg;
            ADDR_INPUT_LEVELS_2: read_value = input_levels_2_reg;
            ADDR_FLAGS:          read_value = flags_reg;
            ADDR_ADC_RESULT:     read_value = {16'b0, adc_result}; // raw ADS1115 counts
            ADDR_RESULT_0:       read_value = result_0;
            ADDR_RESULT_1:       read_value = result_1;
            ADDR_RESULT_2:       read_value = result_2;
            ADDR_DESIGN_ID:      read_value = DESIGN_ID;
            default:             read_value = 32'b0;
        endcase
    end

    assign command           = command_reg[7:0];
    assign row_mask          = row_mask_reg[15:0];
    assign row_index         = row_index_reg[3:0];
    assign column            = column_reg[1:0];
    // Analog routing and column/TIA selection on the current board.
    assign ispp              = switch_ctrl_reg[0];
    assign vp                = switch_ctrl_reg[1];
    assign cc1               = switch_ctrl_reg[2];
    assign cc2               = switch_ctrl_reg[3];
    assign cc3               = switch_ctrl_reg[4];
    assign integrator_reset1 = switch_ctrl_reg[8];
    assign integrator_reset2 = switch_ctrl_reg[9];
    assign integrator_reset3 = switch_ctrl_reg[10];
    assign board_control     = switch_ctrl_reg[16];
    assign dac_a_code        = dac_a_code_reg[15:0]; // TOP_DRIVE
    assign dac_b_code        = dac_b_code_reg[15:0]; // BOT_DRIVE
    assign dac_channel       = dac_channel_reg[0]; // 0=A, 1=B
    assign pulse_cycles      = pulse_cycles_reg;
    assign reset_pulse_cycles = reset_pulse_cycles_reg; // 0 => 1 ms default
    assign t_unit_cycles     = t_unit_cycles_reg;
    assign adc_channel       = adc_channel_reg[2:0]; // firmware channels 1..4
    assign input_levels_0    = input_levels_0_reg;
    assign input_levels_1    = input_levels_1_reg;
    assign input_levels_2    = input_levels_2_reg;
    assign use_offset        = flags_reg[0];
    assign use_integrator    = flags_reg[1];
endmodule
