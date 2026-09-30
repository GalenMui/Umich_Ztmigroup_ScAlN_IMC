// One-clock AXI4-Lite serial replacement for the active Teensy peripherals.
module imc_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SHIFT_HZ = 10_000_000,
    parameter integer LATCH_US = 1,
    parameter integer DAC_SPI_HZ = 30_000_000,
    parameter integer ADC_I2C_HZ = 100_000
) (
    input  logic s_axi_aclk, s_axi_aresetn,
    input  logic [7:0] s_axi_awaddr,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0] s_axi_wstrb,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    input  logic [7:0] s_axi_araddr,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input  logic s_axi_rready,
    output logic sr_data, sr_clk, sr_latch, sr_oe_n,
    output logic dac_sclk, dac_mosi, dac_cs_n, dac_reset_n,
    output logic adc_scl_drive_low, adc_sda_drive_low,
    input  logic adc_sda_in,
    output logic ispp, vp, cc1, cc2, cc3,
    output logic integrator_reset1, integrator_reset2, integrator_reset3,
    output logic board_control, timing_pulse
);
    localparam logic [7:0] ERR_BUSY = 8'h01, ERR_COMMAND = 8'h02,
                           ERR_ABORTED = 8'h03;
    localparam logic [31:0] ONE_MS = CLK_HZ / 1000;
    typedef enum logic [3:0] {
        INIT_ROW, INIT_DAC_RESET, INIT_DELAY, INIT_DAC_REF,
        INIT_DAC_A, INIT_DAC_B, IDLE, RUN_ROW, RUN_DAC,
        RUN_ADC, RUN_RESET, RUN_DELAY
    } state_t;
    state_t state;
    logic start_pulse, clear_done_pulse, soft_reset_pulse, abort_pulse;
    logic [7:0] command;
    logic [15:0] row_mask, dac_a_code, dac_b_code;
    logic [15:0] row_mask_active;
    logic dac_channel;
    logic [2:0] adc_channel;
    logic [2:0] adc_channel_active;
    logic [31:0] pulse_cycles, reset_pulse_cycles;
    logic staged_ispp, staged_vp, staged_cc1, staged_cc2, staged_cc3;
    logic staged_reset1, staged_reset2, staged_reset3, staged_board;
    logic [8:0] switch_active;
    logic row_start, row_busy, row_done, row_initialized;
    logic dac_start, dac_busy, dac_done;
    logic [2:0] dac_operation;
    logic [15:0] dac_code;
    logic adc_start, adc_busy, adc_done, adc_valid;
    logic adc_probe;
    logic signed [15:0] adc_raw;
    logic [7:0] adc_error;
    logic init_timer_start, init_timer_busy, init_timer_done;
    logic reset_timer_start, reset_timer_busy, reset_timer_done, reset_pulse;
    logic delay_timer_start, delay_timer_busy, delay_timer_done;
    logic [31:0] reset_timer_cycles, delay_timer_cycles;
    logic safe_request, restart_safe, initialized_flag, safe_pending;
    logic done_sticky, error_sticky, adc_valid_sticky;
    logic [7:0] error_code;
    logic [15:0] adc_result;
    logic busy;

    assign safe_request = start_pulse && state == IDLE &&
                          (command == 8'h01 || command == 8'h7F);
    assign restart_safe = soft_reset_pulse || abort_pulse || safe_request;
    assign busy = state != IDLE;
    assign dac_reset_n = 1'b1; // Teensy leaves hardware RESET# released.
    assign {board_control, integrator_reset3, integrator_reset2,
            integrator_reset1, cc3, cc2, cc1, vp, ispp} =
            {switch_active[8],
             switch_active[7:5] | {3{reset_pulse}}, switch_active[4:0]};

    row_shift_controller #(.CLK_HZ(CLK_HZ), .SHIFT_HZ(SHIFT_HZ),
                           .LATCH_US(LATCH_US)) u_rows (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn), .start(row_start),
        .mask(row_mask_active), .restart_safe(restart_safe), .sr_data, .sr_clk,
        .sr_latch, .sr_oe_n, .busy(row_busy), .done_pulse(row_done),
        .initialized(row_initialized)
    );
    ad5689_controller #(.CLK_HZ(CLK_HZ), .SPI_HZ(DAC_SPI_HZ)) u_dac (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn), .start(dac_start),
        .abort(restart_safe), .operation(dac_operation), .code(dac_code),
        .sclk(dac_sclk), .mosi(dac_mosi), .cs_n(dac_cs_n),
        .busy(dac_busy), .done_pulse(dac_done)
    );
    ads1115_controller #(.CLK_HZ(CLK_HZ), .I2C_HZ(ADC_I2C_HZ)) u_adc (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn), .start(adc_start),
        .abort(restart_safe), .probe(adc_probe), .channel(adc_channel_active),
        .sda_in(adc_sda_in), .scl_drive_low(adc_scl_drive_low),
        .sda_drive_low(adc_sda_drive_low), .raw_result(adc_raw),
        .busy(adc_busy), .done_pulse(adc_done), .valid(adc_valid),
        .error_code(adc_error)
    );
    cycle_timer u_init_timer (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn), .start(init_timer_start),
        .abort(restart_safe), .cycles(ONE_MS), .pulse_out(),
        .busy(init_timer_busy), .done_pulse(init_timer_done)
    );
    cycle_timer u_reset_timer (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn), .start(reset_timer_start),
        .abort(restart_safe), .cycles(reset_timer_cycles),
        .pulse_out(reset_pulse), .busy(reset_timer_busy),
        .done_pulse(reset_timer_done)
    );
    cycle_timer u_delay_timer (
        .clk(s_axi_aclk), .resetn(s_axi_aresetn), .start(delay_timer_start),
        .abort(restart_safe), .cycles(delay_timer_cycles),
        .pulse_out(timing_pulse), .busy(delay_timer_busy),
        .done_pulse(delay_timer_done)
    );

    control_regs u_control_regs (
        .s_axi_aclk, .s_axi_aresetn, .s_axi_awaddr, .s_axi_awvalid,
        .s_axi_awready, .s_axi_wdata, .s_axi_wstrb, .s_axi_wvalid,
        .s_axi_wready, .s_axi_bresp, .s_axi_bvalid, .s_axi_bready,
        .s_axi_araddr, .s_axi_arvalid, .s_axi_arready, .s_axi_rdata,
        .s_axi_rresp, .s_axi_rvalid, .s_axi_rready,
        .start_pulse, .clear_done_pulse, .soft_reset_pulse, .abort_pulse,
        .command, .row_mask, .row_index(), .column(),
        .ispp(staged_ispp), .vp(staged_vp), .cc1(staged_cc1),
        .cc2(staged_cc2), .cc3(staged_cc3),
        .integrator_reset1(staged_reset1),
        .integrator_reset2(staged_reset2),
        .integrator_reset3(staged_reset3),
        .board_control(staged_board), .dac_a_code, .dac_b_code,
        .dac_channel, .pulse_cycles, .reset_pulse_cycles,
        .t_unit_cycles(), .adc_channel, .input_levels_0(),
        .input_levels_1(), .input_levels_2(), .use_offset(),
        .use_integrator(), .clear_switch_ctrl(restart_safe),
        .busy, .done(done_sticky), .error(error_sticky),
        .adc_valid(adc_valid_sticky), .initialized(initialized_flag),
        .error_code, .adc_result, .result_0(32'b0),
        .result_1(32'b0), .result_2(32'b0)
    );

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            state <= INIT_ROW;
            row_start <= 0;
            dac_start <= 0;
            dac_operation <= 0;
            dac_code <= 0;
            row_mask_active <= 16'hFFFF;
            adc_channel_active <= 0;
            adc_start <= 0;
            adc_probe <= 0;
            init_timer_start <= 0;
            reset_timer_start <= 0;
            delay_timer_start <= 0;
            reset_timer_cycles <= 0;
            delay_timer_cycles <= 0;
            switch_active <= 0;
            initialized_flag <= 0;
            safe_pending <= 0;
            done_sticky <= 0;
            error_sticky <= 0;
            adc_valid_sticky <= 0;
            error_code <= 0;
            adc_result <= 0;
        end else begin
            row_start <= 0;
            dac_start <= 0;
            adc_start <= 0;
            init_timer_start <= 0;
            reset_timer_start <= 0;
            delay_timer_start <= 0;
            if (restart_safe) begin
                state <= INIT_ROW;
                switch_active <= 0;
                initialized_flag <= 0;
                safe_pending <= safe_request;
                done_sticky <= 0;
                adc_valid_sticky <= 0;
                if (abort_pulse && busy) begin
                    error_sticky <= 1;
                    error_code <= ERR_ABORTED;
                end else begin
                    error_sticky <= 0;
                    error_code <= 0;
                end
            end else begin
                if (clear_done_pulse) done_sticky <= 0;
                if (start_pulse && busy) begin
                    error_sticky <= 1;
                    error_code <= ERR_BUSY;
                end
                case (state)
                    INIT_ROW: if (row_initialized) begin
                        dac_operation <= 3'd0;
                        dac_start <= 1;
                        state <= INIT_DAC_RESET;
                    end
                    INIT_DAC_RESET: if (dac_done) begin
                        init_timer_start <= 1;
                        state <= INIT_DELAY;
                    end
                    INIT_DELAY: if (init_timer_done) begin
                        dac_operation <= 3'd1;
                        dac_start <= 1;
                        state <= INIT_DAC_REF;
                    end
                    INIT_DAC_REF: if (dac_done) begin
                        dac_operation <= 3'd2;
                        dac_start <= 1;
                        state <= INIT_DAC_A;
                    end
                    INIT_DAC_A: if (dac_done) begin
                        dac_operation <= 3'd3;
                        dac_start <= 1;
                        state <= INIT_DAC_B;
                    end
                    INIT_DAC_B: if (dac_done) begin
                        initialized_flag <= 1;
                        if (safe_pending) done_sticky <= 1;
                        safe_pending <= 0;
                        state <= IDLE;
                    end
                    IDLE: if (start_pulse) begin
                        done_sticky <= 0;
                        error_sticky <= 0;
                        error_code <= 0;
                        adc_valid_sticky <= 0;
                        case (command)
                            8'h02: begin
                                row_mask_active <= row_mask;
                                row_start <= 1;
                                state <= RUN_ROW;
                            end
                            8'h03: begin
                                dac_operation <= dac_channel ? 3'd5 : 3'd4;
                                dac_code <= dac_channel ? dac_b_code : dac_a_code;
                                dac_start <= 1;
                                state <= RUN_DAC;
                            end
                            8'h04, 8'h08: begin
                                adc_channel_active <= adc_channel;
                                adc_probe <= command == 8'h08;
                                adc_start <= 1;
                                state <= RUN_ADC;
                            end
                            8'h05: begin
                                switch_active <= {staged_board, staged_reset3,
                                    staged_reset2, staged_reset1, staged_cc3,
                                    staged_cc2, staged_cc1, staged_vp, staged_ispp};
                                done_sticky <= 1;
                            end
                            8'h06: begin
                                reset_timer_cycles <= reset_pulse_cycles == 0 ?
                                    ONE_MS : reset_pulse_cycles;
                                reset_timer_start <= 1;
                                state <= RUN_RESET;
                            end
                            8'h07: begin
                                delay_timer_cycles <= pulse_cycles;
                                delay_timer_start <= 1;
                                state <= RUN_DELAY;
                            end
                            default: begin
                                error_sticky <= 1;
                                error_code <= ERR_COMMAND;
                                done_sticky <= 1;
                            end
                        endcase
                    end
                    RUN_ROW: if (row_done) begin
                        done_sticky <= 1;
                        state <= IDLE;
                    end
                    RUN_DAC: if (dac_done) begin
                        done_sticky <= 1;
                        state <= IDLE;
                    end
                    RUN_ADC: if (adc_done) begin
                        adc_result <= adc_raw;
                        adc_valid_sticky <= adc_valid;
                        if (!adc_valid) begin
                            error_sticky <= 1;
                            error_code <= adc_error;
                        end
                        done_sticky <= 1;
                        state <= IDLE;
                    end
                    RUN_RESET: if (reset_timer_done) begin
                        done_sticky <= 1;
                        state <= IDLE;
                    end
                    RUN_DELAY: if (delay_timer_done) begin
                        done_sticky <= 1;
                        state <= IDLE;
                    end
                    default: state <= INIT_ROW;
                endcase
            end
        end
    end
endmodule
