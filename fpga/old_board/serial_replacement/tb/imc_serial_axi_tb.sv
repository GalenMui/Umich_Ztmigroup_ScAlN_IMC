`timescale 1ns/1ps
module imc_serial_axi_tb;
    localparam logic [7:0] CONTROL=8'h00, STATUS=8'h04, COMMAND=8'h08,
        ERROR_REG=8'h0C, ROW_MASK=8'h10, SWITCH_CTRL=8'h1C,
        DAC_A_CODE=8'h20, DAC_B_CODE=8'h24, PULSE_CYCLES=8'h28,
        ADC_CHANNEL=8'h30, DAC_CHANNEL=8'h34, RESET_CYCLES=8'h38,
        ADC_RESULT=8'h60;
    localparam logic [31:0] BUSY=1, DONE=2, ERROR=4, ADC_VALID=8, INIT=16;
    logic clk=0;
    always #25 clk=~clk; // 20 MHz test clock, demonstrating parameter override.
    logic resetn=0;
    logic [7:0] awaddr=0, araddr=0;
    logic awvalid=0, wvalid=0, bready=0, arvalid=0, rready=0;
    logic [31:0] wdata=0;
    logic [3:0] wstrb=4'hF;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    wire sr_data,sr_clk,sr_latch,sr_oe_n;
    wire dac_sclk,dac_mosi,dac_cs_n,dac_reset_n;
    wire adc_scl_low,adc_sda_low,slave_sda_low;
    wire scl_line=~adc_scl_low, sda_line=~(adc_sda_low | slave_sda_low);
    wire ispp,vp,cc1,cc2,cc3,reset1,reset2,reset3,board_control,timing_pulse;
    wire [23:0] last_dac_frame;
    wire [15:0] last_adc_config;
    logic [23:0] dac_history [0:255];
    integer dac_frames, config_writes, config_reads, conversion_reads;
    always @(dac_frames) if (dac_frames > 0 && dac_frames <= 256)
        dac_history[dac_frames-1] = last_dac_frame;

    imc_top #(.CLK_HZ(20_000_000), .SHIFT_HZ(1_000_000),
              .DAC_SPI_HZ(2_500_000), .ADC_I2C_HZ(100_000)) dut (
        .s_axi_aclk(clk), .s_axi_aresetn(resetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
        .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .sr_data, .sr_clk, .sr_latch, .sr_oe_n,
        .dac_sclk, .dac_mosi, .dac_cs_n, .dac_reset_n,
        .adc_scl_drive_low(adc_scl_low),
        .adc_sda_drive_low(adc_sda_low), .adc_sda_in(sda_line),
        .ispp, .vp, .cc1, .cc2, .cc3,
        .integrator_reset1(reset1), .integrator_reset2(reset2),
        .integrator_reset3(reset3), .board_control, .timing_pulse
    );
    ad5689_spi_monitor dac_model (
        .cs_n(dac_cs_n), .sclk(dac_sclk), .mosi(dac_mosi),
        .last_frame(last_dac_frame), .frame_count(dac_frames)
    );
    ads1115_i2c_model adc_model (
        .scl(scl_line), .sda(sda_line), .sda_drive_low(slave_sda_low),
        .last_config(last_adc_config), .config_writes,
        .config_reads, .conversion_reads
    );

    task automatic axi_write(input logic [7:0] addr,input logic [31:0] data);
        begin
            @(negedge clk); awaddr=addr; awvalid=1; wdata=data; wvalid=1;
            wait(awready && wready); @(posedge clk); #1;
            awvalid=0; wvalid=0; bready=1;
            wait(bvalid); @(posedge clk); #1; bready=0;
        end
    endtask
    task automatic axi_read(input logic [7:0] addr,output logic [31:0] data);
        begin
            @(negedge clk); araddr=addr; arvalid=1;
            wait(arready); @(posedge clk); #1; arvalid=0;
            wait(rvalid); data=rdata;
            @(negedge clk); rready=1; @(posedge clk); #1; rready=0;
        end
    endtask
    task automatic wait_bits(input logic [31:0] wanted);
        logic [31:0] status_value;
        integer tries;
        begin
            tries=0; status_value=0;
            while ((status_value & wanted) != wanted && tries < 500000) begin
                axi_read(STATUS,status_value);
                tries=tries+1;
            end
            if ((status_value & wanted) != wanted)
                $fatal(1,"status timeout wanted=%h last=%h",wanted,status_value);
        end
    endtask
    task automatic issue(input logic [7:0] cmd);
        begin
            axi_write(COMMAND,{24'h0,cmd});
            axi_write(CONTROL,32'h1);
        end
    endtask
    task automatic run_dac(input logic channel_b,input logic [15:0] code);
        integer before_count;
        logic [31:0] status_value;
        logic [23:0] expected;
        begin
            before_count=dac_frames;
            axi_write(DAC_CHANNEL,{31'b0,channel_b});
            axi_write(channel_b ? DAC_B_CODE : DAC_A_CODE,{16'h0,code});
            issue(8'h03); wait_bits(DONE);
            expected={channel_b ? 8'h38 : 8'h31,code};
            if (dac_frames!=before_count+1 || last_dac_frame !== expected)
                $fatal(1,"DAC frame got %h expected %h",last_dac_frame,expected);
            axi_read(STATUS,status_value);
            if ((status_value & (BUSY|ERROR)) != 0) $fatal(1,"DAC status error");
        end
    endtask
    task automatic run_adc(input logic [2:0] channel,
                           input logic [15:0] sample);
        logic [31:0] data;
        logic [15:0] expected_cfg;
        integer before_reads;
        begin
            adc_model.conversion_word=sample;
            before_reads=conversion_reads;
            axi_write(ADC_CHANNEL,{29'b0,channel});
            issue(8'h04); wait_bits(DONE);
            axi_read(STATUS,data);
            if ((data & (ERROR|ADC_VALID)) != ADC_VALID)
                $fatal(1,"ADC completion status %h",data);
            axi_read(ADC_RESULT,data);
            if (data !== {16'h0000,sample})
                $fatal(1,"ADC result got %h expected %h",data,sample);
            case(channel)
                1: expected_cfg=16'hC3E3;
                2: expected_cfg=16'hD3E3;
                3: expected_cfg=16'hE3E3;
                default: expected_cfg=16'hF3E3;
            endcase
            if (last_adc_config !== expected_cfg || conversion_reads != before_reads+1)
                $fatal(1,"ADC protocol/config mismatch %h",last_adc_config);
        end
    endtask

    integer i, before_count, starts_before, stops_before;
    logic [15:0] random_code;
    logic [31:0] value;
    time rise_time, fall_time;
    time timer_rise, timer_fall;
    integer timer_edges=0;
    logic watch_reset=0;
    always @(posedge reset1) rise_time=$time;
    always @(negedge reset1) fall_time=$time;
    always @(posedge reset1 or posedge reset2 or posedge reset3)
        if (watch_reset) begin
            #1;
            if ({reset1,reset2,reset3}!==3'b111)
                $fatal(1,"integrator reset assertion was not simultaneous");
        end
    always @(negedge reset1 or negedge reset2 or negedge reset3)
        if (watch_reset) begin
            #1;
            if ({reset1,reset2,reset3}!==3'b000)
                $fatal(1,"integrator reset release was not simultaneous");
        end
    always @(posedge timing_pulse) begin timer_rise=$time; timer_edges=timer_edges+1; end
    always @(negedge timing_pulse) timer_fall=$time;
    initial begin
        repeat(3) @(posedge clk);
        #1;
        if (sr_oe_n!==1 || dac_cs_n!==1 || dac_sclk!==0 ||
            adc_scl_low!==0 || adc_sda_low!==0 ||
            {ispp,vp,cc1,cc2,cc3,reset1,reset2,reset3} !== 0)
            $fatal(1,"unsafe startup pins");
        @(negedge clk); resetn=1;
        wait_bits(INIT);
        if (dac_frames!=4 || dac_history[0]!==24'h60_0000 ||
            dac_history[1]!==24'h70_0000 ||
            dac_history[2]!==24'h31_0000 ||
            dac_history[3]!==24'h38_0000 || sr_oe_n!==0)
            $fatal(1,"startup frame sequence incorrect");
        run_dac(0,16'h0000);
        run_dac(1,16'hFFFF);
        run_dac(0,16'hA5C3);
        for(i=0;i<32;i=i+1) begin
            random_code=16'($urandom);
            run_dac(1'(i[0]),random_code);
        end

        // Active code is snapshotted while the AXI staging register remains writable.
        before_count=dac_frames;
        axi_write(DAC_CHANNEL,0);
        axi_write(DAC_A_CODE,32'h0000_BEEF);
        issue(8'h03);
        axi_write(DAC_A_CODE,32'h0000_1234);
        wait_bits(DONE);
        if (dac_frames!=before_count+1 || last_dac_frame!==24'h31_BEEF)
            $fatal(1,"DAC snapshot failed");

        // A second start during an active DAC frame must be rejected.
        before_count=dac_frames;
        axi_write(DAC_A_CODE,32'h0000_CAFE);
        issue(8'h03);
        axi_write(DAC_CHANNEL,1);
        axi_write(DAC_B_CODE,32'h0000_DEAD);
        issue(8'h03);
        axi_read(ERROR_REG,value);
        if (value!==1) $fatal(1,"busy DAC start not rejected");
        wait_bits(DONE);
        if (dac_frames!=before_count+1 || last_dac_frame!==24'h31_CAFE)
            $fatal(1,"busy DAC start corrupted active frame");

        // Routing register is staged; SET_SWITCHES applies all named bits together.
        axi_write(SWITCH_CTRL,32'h0000_0115);
        if ({ispp,vp,cc1,cc2,cc3,reset1,reset2,reset3} !== 0)
            $fatal(1,"routing changed before command");
        issue(8'h05); wait_bits(DONE);
        if ({ispp,vp,cc1,cc2,cc3,reset1,reset2,reset3} !== 8'b10101100)
            $fatal(1,"routing bit mapping failed");
        axi_write(SWITCH_CTRL,0); issue(8'h05); wait_bits(DONE);

        // Exact N-cycle pulse, with all three logical RESET lines simultaneous.
        axi_write(RESET_CYCLES,32'd20);
        watch_reset=1;
        issue(8'h06);
        wait_bits(DONE);
        if (fall_time-rise_time!=1000 || reset2 || reset3)
            $fatal(1,"reset pulse width incorrect: %0t",fall_time-rise_time);
        axi_write(RESET_CYCLES,0);
        issue(8'h06); wait_bits(DONE);
        if (fall_time-rise_time!=1_000_000)
            $fatal(1,"default 1 ms reset pulse width incorrect");
        watch_reset=0;
        axi_write(PULSE_CYCLES,32'd7);
        issue(8'h07);
        wait_bits(DONE);
        if (timer_fall-timer_rise!=350) $fatal(1,"timer width incorrect");
        before_count=timer_edges;
        axi_write(PULSE_CYCLES,0); issue(8'h07); wait_bits(DONE);
        if (timer_edges!=before_count) $fatal(1,"zero-cycle timer pulsed");
        axi_write(PULSE_CYCLES,1); issue(8'h07); wait_bits(DONE);
        if (timer_edges!=before_count+1 || timer_fall-timer_rise!=50)
            $fatal(1,"one-cycle timer width incorrect");

        // One owner: a DAC request cannot preempt an active timer.
        axi_write(PULSE_CYCLES,32'd1000);
        issue(8'h07);
        before_count=dac_frames;
        issue(8'h03);
        axi_read(ERROR_REG,value);
        if (value!==1 || dac_frames!=before_count)
            $fatal(1,"overlap not rejected");
        wait_bits(DONE);

        starts_before=adc_model.start_count;
        stops_before=adc_model.stop_count;
        run_adc(3'd1,16'h1234);
        run_adc(3'd2,16'hF234);
        run_adc(3'd3,16'h7FFF);
        if (config_reads < 6 || config_writes < 3)
            $fatal(1,"ADC ready polling not exercised");
        // Each register read uses a repeated START with no intervening STOP.
        if (adc_model.start_count-starts_before !==
              3 + 2*(config_reads+conversion_reads) ||
            adc_model.stop_count-stops_before !==
              3 + config_reads+conversion_reads)
            $fatal(1,"ADS1115 repeated-START/STOP sequence incorrect");

        adc_model.conversion_word=16'hA55A;
        axi_write(ADC_CHANNEL,1);
        issue(8'h04);
        axi_write(ADC_CHANNEL,3);
        wait_bits(DONE);
        if (last_adc_config!==16'hC3E3)
            $fatal(1,"ADC channel was not snapshotted");
        axi_read(ADC_RESULT,value);
        if (value!==32'h0000_A55A) $fatal(1,"ADC snapshot result mismatch");

        // Teensy adc_init() reads config for presence without a conversion.
        before_count=config_writes;
        axi_write(ADC_CHANNEL,0);
        issue(8'h08); wait_bits(DONE);
        axi_read(STATUS,value);
        if ((value & (ERROR|ADC_VALID)) != ADC_VALID ||
            config_writes!=before_count)
            $fatal(1,"ADS1115 config-only probe failed");
        axi_read(ADC_RESULT,value);
        if (value[15:0]!==last_adc_config)
            $fatal(1,"ADS1115 probe config mismatch");
        adc_model.nack_next_address=1;
        issue(8'h08); wait_bits(DONE);
        axi_read(ERROR_REG,value);
        if (value!==8'h10) $fatal(1,"ADS1115 probe NACK not reported");

        axi_write(ADC_CHANNEL,0); issue(8'h04); wait_bits(DONE);
        axi_read(ERROR_REG,value);
        if (value!==8'h12) $fatal(1,"invalid ADC channel not rejected");

        adc_model.nack_next_address=1;
        axi_write(ADC_CHANNEL,1); issue(8'h04); wait_bits(DONE);
        axi_read(ERROR_REG,value);
        if (value!==8'h10) $fatal(1,"NACK code incorrect %h",value);

        adc_model.force_never_ready=1;
        axi_write(ADC_CHANNEL,1); issue(8'h04); wait_bits(DONE);
        axi_read(ERROR_REG,value);
        if (value!==8'h11) $fatal(1,"timeout code incorrect %h",value);
        adc_model.force_never_ready=0;

        // Abort restarts row and DAC initialization and clears routing outputs.
        axi_write(PULSE_CYCLES,32'd1000); issue(8'h07);
        axi_write(CONTROL,32'h08);
        if (sr_oe_n!==1 || dac_cs_n!==1 || {ispp,vp,cc1,cc2,cc3}!==0)
            $fatal(1,"abort failed to drive safe digital pins");
        wait_bits(INIT);
        if (sr_oe_n!==0 || dac_frames<8) $fatal(1,"abort reinit failed");
        issue(8'h7F); wait_bits(DONE | INIT);
        if ({ispp,vp,cc1,cc2,cc3,reset1,reset2,reset3}!==0 ||
            sr_oe_n!==0 || dac_history[dac_frames-1]!==24'h38_0000)
            $fatal(1,"safe-state reinit failed");
        axi_write(CONTROL,32'h04);
        wait_bits(INIT);
        if (sr_oe_n!==0 || {ispp,vp,cc1,cc2,cc3}!==0)
            $fatal(1,"soft reset reinit failed");
        $display("PASS: serial AXI integration, DAC, ADS1115, routing, timers, arbitration, abort");
        $finish;
    end
    initial begin
        #100_000_000;
        $fatal(1,"global integration timeout");
    end
endmodule
