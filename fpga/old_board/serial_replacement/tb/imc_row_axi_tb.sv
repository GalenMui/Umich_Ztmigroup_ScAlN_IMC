`timescale 1ns/1ps

module imc_row_axi_tb;
    localparam logic [7:0] CONTROL = 8'h00, STATUS = 8'h04,
                           COMMAND = 8'h08, ERROR_REG = 8'h0C,
                           ROW_MASK = 8'h10, DESIGN_ID = 8'hFC;
    localparam logic [31:0] BUSY = 1, DONE = 2, ERROR = 4, INITIALIZED = 16;

    logic clk = 0;
    always #5 clk = ~clk; // 100 MHz
    logic resetn = 0;
    logic [7:0] awaddr = 0, araddr = 0;
    logic awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [31:0] wdata = 0;
    logic [3:0] wstrb = 4'hF;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire sr_data, sr_clk, sr_latch, sr_oe_n;

    imc_top #(.CLK_HZ(100_000_000), .SHIFT_HZ(10_000_000), .LATCH_US(1)) dut (
        .s_axi_aclk(clk), .s_axi_aresetn(resetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
        .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .sr_data(sr_data), .sr_clk(sr_clk), .sr_latch(sr_latch), .sr_oe_n(sr_oe_n)
    );

    // Independent physical model: the near 595 Q7' enters the far 595.
    logic [7:0] near_shift = 8'h00, far_shift = 8'h00;
    logic [7:0] near_store = 8'h5A, far_store = 8'hA5;
    wire [15:0] parallel_rc = {far_store, near_store};
    logic [15:0] previous_parallel = 16'hA55A;
    integer rising_edges = 0, latch_edges = 0, burst_edges = 0;
    time last_data_change = 0, last_rise = 0, latch_rise = 0;
    logic have_last_rise = 0;
    logic oe_was_enabled = 0;

    always @(sr_data) last_data_change = $time;
    always @(posedge sr_clk) begin
        if (sr_latch !== 1'b0) $fatal(1, "shift edge while latch high");
        if (parallel_rc !== previous_parallel)
            $fatal(1, "595 parallel outputs changed before STCP");
        if ($time - last_data_change < 10) $fatal(1, "data setup time too short");
        if (have_last_rise && $time - last_rise != 100)
            $fatal(1, "SHCP period is not 100 ns");
        have_last_rise = 1;
        last_rise = $time;
        rising_edges = rising_edges + 1;
        burst_edges = burst_edges + 1;
        far_shift <= {far_shift[6:0], near_shift[7]};
        near_shift <= {near_shift[6:0], sr_data};
    end
    always @(posedge sr_latch) begin
        if (sr_clk !== 1'b0 || burst_edges != 16)
            $fatal(1, "latch without exactly 16 shift edges");
        latch_rise = $time;
        latch_edges = latch_edges + 1;
        burst_edges = 0;
        have_last_rise = 0;
        far_store <= far_shift;
        near_store <= near_shift;
    end
    always @(negedge sr_latch) begin
        if (resetn && latch_rise != 0 && $time - latch_rise != 1000)
            $fatal(1, "STCP high time is not 1 us");
        previous_parallel = parallel_rc;
    end
    always @(posedge sr_oe_n or negedge resetn) begin
        burst_edges = 0;
        have_last_rise = 0;
    end
    always @(negedge sr_oe_n) begin
        if (parallel_rc !== 16'hFFFF)
            $fatal(1, "OE enabled before deselect was latched");
        oe_was_enabled = 1;
    end

    task automatic axi_write(input logic [7:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1; wdata = data; wvalid = 1;
            wait (awready && wready);
            @(posedge clk); #1;
            awvalid = 0; wvalid = 0; bready = 1;
            wait (bvalid);
            @(posedge clk); #1;
            bready = 0;
        end
    endtask

    task automatic axi_write_split(input logic [7:0] addr, input logic [31:0] data);
        begin
            @(negedge clk); awaddr = addr; awvalid = 1;
            wait (awready); @(posedge clk); #1; awvalid = 0;
            repeat (3) @(posedge clk);
            @(negedge clk); wdata = data; wvalid = 1;
            wait (wready); @(posedge clk); #1; wvalid = 0; bready = 1;
            wait (bvalid); @(posedge clk); #1; bready = 0;
        end
    endtask

    task automatic axi_read(input logic [7:0] addr, output logic [31:0] value);
        begin
            @(negedge clk); araddr = addr; arvalid = 1;
            wait (arready); @(posedge clk); #1; arvalid = 0;
            wait (rvalid); value = rdata;
            @(negedge clk); rready = 1;
            @(posedge clk); #1; rready = 0;
        end
    endtask

    task automatic wait_status(input logic [31:0] wanted);
        logic [31:0] value;
        integer attempts;
        begin
            value = 0; attempts = 0;
            while ((value & wanted) != wanted && attempts < 100000) begin
                axi_read(STATUS, value);
                attempts = attempts + 1;
            end
            if ((value & wanted) != wanted) $fatal(1, "status timeout: %h", wanted);
        end
    endtask

    task automatic command_mask(input logic [15:0] value);
        begin
            axi_write(ROW_MASK, {16'h0000, value});
            axi_write(COMMAND, 32'h02);
            axi_write(CONTROL, 32'h01);
        end
    endtask

    task automatic check_mask(input logic [15:0] value);
        integer before_edges, before_latches;
        logic [31:0] status_value;
        begin
            before_edges = rising_edges;
            before_latches = latch_edges;
            command_mask(value);
            axi_read(STATUS, status_value);
            if ((status_value & BUSY) == 0) $fatal(1, "busy not asserted");
            wait_status(DONE);
            repeat (5) @(posedge clk);
            if (rising_edges - before_edges != 16 || latch_edges - before_latches != 1)
                $fatal(1, "wrong transfer size for %h", value);
            if (parallel_rc !== value) $fatal(1, "RC mismatch: got %h expected %h", parallel_rc, value);
            axi_read(STATUS, status_value);
            if ((status_value & (BUSY | ERROR | INITIALIZED | DONE)) != (INITIALIZED | DONE))
                $fatal(1, "wrong completion status: %h", status_value);
        end
    endtask

    integer i, before_edges, before_latches;
    logic [15:0] random_mask;
    logic [31:0] value;
    initial begin
        repeat (3) @(posedge clk);
        #1;
        if (sr_oe_n !== 1'b1 || sr_clk !== 1'b0 || sr_latch !== 1'b0)
            $fatal(1, "unsafe reset pins");
        @(negedge clk); resetn = 1;
        axi_read(STATUS, value);
        if ((value & BUSY) == 0 || (value & INITIALIZED) != 0 || sr_oe_n !== 1'b1)
            $fatal(1, "startup did not report busy with OE disabled");
        wait_status(INITIALIZED);
        if (!oe_was_enabled || rising_edges != 16 || latch_edges != 1 ||
            parallel_rc !== 16'hFFFF || sr_oe_n !== 1'b0)
            $fatal(1, "startup initialization failed");
        axi_read(DESIGN_ID, value);
        if (value !== 32'h0001_0001) $fatal(1, "DESIGN_ID mismatch");

        check_mask(16'hFFFF);
        check_mask(16'hFFFE); // RC1
        check_mask(16'hFFFD); // RC2
        check_mask(16'hF7FF); // RC12; unused bits 12..15 stay high
        for (i = 1; i <= 12; i = i + 1) begin
            random_mask = ~(16'h0001 << (i - 1));
            if (random_mask[15:12] !== 4'hF) $fatal(1, "unused bits not high");
            check_mask(random_mask);
        end
        for (i = 0; i < 64; i = i + 1) begin
            random_mask = 16'($urandom);
            check_mask(random_mask);
        end

        // Exercise split AXI address/data arrival and sticky-done clearing.
        axi_write_split(CONTROL, 32'h02);
        axi_read(STATUS, value);
        if ((value & DONE) != 0) $fatal(1, "clear_done failed");

        // Change ROW_MASK and issue a second start while the first is active.
        before_edges = rising_edges; before_latches = latch_edges;
        command_mask(16'hA55A);
        axi_write(ROW_MASK, 32'h0000_0F0F);
        axi_write(CONTROL, 32'h01);
        axi_read(STATUS, value);
        if ((value & ERROR) == 0) $fatal(1, "busy start not rejected");
        axi_read(ERROR_REG, value);
        if (value !== 1) $fatal(1, "wrong busy error code");
        wait_status(DONE);
        if (parallel_rc !== 16'hA55A || rising_edges - before_edges != 16 ||
            latch_edges - before_latches != 1)
            $fatal(1, "active mask was corrupted");
        // A later accepted start uses the new register value and clears error.
        check_mask(16'h0F0F);

        // Unsupported command is rejected without any shift edges.
        before_edges = rising_edges;
        axi_write(COMMAND, 32'h10); // READ_CELL remains unimplemented.
        axi_write(CONTROL, 32'h01);
        axi_read(ERROR_REG, value);
        if (value !== 2 || rising_edges != before_edges)
            $fatal(1, "unsupported command handling failed");

        // Abort mid-shift disables outputs and runs the safe sequence again.
        command_mask(16'h0000);
        repeat (4) @(posedge sr_clk);
        axi_write(CONTROL, 32'h08);
        if (sr_oe_n !== 1'b1) $fatal(1, "abort did not disable OE");
        wait_status(INITIALIZED);
        if (parallel_rc !== 16'hFFFF || sr_oe_n !== 1'b0)
            $fatal(1, "abort did not restore deselect");
        axi_read(STATUS, value);
        if ((value & DONE) != 0) $fatal(1, "aborted transfer reported done");

        // Soft reset uses the same disabled-output reinitialization path.
        command_mask(16'h1234);
        repeat (4) @(posedge sr_clk);
        axi_write(CONTROL, 32'h04);
        if (sr_oe_n !== 1'b1) $fatal(1, "soft reset did not disable OE");
        wait_status(INITIALIZED);
        axi_read(STATUS, value);
        if (parallel_rc !== 16'hFFFF || sr_oe_n !== 1'b0 ||
            (value & (DONE | ERROR)) != 0)
            $fatal(1, "soft reset did not restore clean deselect");

        // Hardware reset during an active request also restores safe startup.
        command_mask(16'h0000);
        repeat (4) @(posedge sr_clk);
        @(negedge clk); resetn = 0;
        #1;
        if (sr_oe_n !== 1'b1 || sr_clk !== 1'b0 || sr_latch !== 1'b0)
            $fatal(1, "reset did not disable row interface");
        repeat (2) @(posedge clk);
        @(negedge clk); resetn = 1;
        wait_status(INITIALIZED);
        if (parallel_rc !== 16'hFFFF || sr_oe_n !== 1'b0)
            $fatal(1, "reset did not restore deselect");
        check_mask(16'hFFFE);
        $display("PASS: AXI row control, startup, 80 masks, snapshot, abort, soft reset, reset");
        $finish;
    end

    initial begin
        #20_000_000;
        $fatal(1, "global test timeout");
    end
endmodule
