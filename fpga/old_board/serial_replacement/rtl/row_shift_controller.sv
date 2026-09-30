module row_shift_controller #(
    parameter integer CLK_HZ   = 100_000_000,
    parameter integer SHIFT_HZ = 10_000_000,
    parameter integer LATCH_US = 1
) (
    input  logic        clk,
    input  logic        resetn,
    input  logic        start,
    input  logic [15:0] mask,
    input  logic        restart_safe,
    output logic        sr_data,
    output logic        sr_clk,
    output logic        sr_latch,
    output logic        sr_oe_n,
    output logic        busy,
    output logic        done_pulse,
    output logic        initialized
);
    localparam integer HALF_CYCLES = CLK_HZ / (2 * SHIFT_HZ);
    localparam longint unsigned LATCH_CYCLES =
        ((64'd1 * CLK_HZ * LATCH_US) + 999_999) / 1_000_000;
    localparam integer HALF_WIDTH = (HALF_CYCLES < 2) ? 1 : $clog2(HALF_CYCLES);
    localparam integer LATCH_WIDTH = (LATCH_CYCLES < 2) ? 1 : $clog2(LATCH_CYCLES);
    localparam logic [HALF_WIDTH-1:0] HALF_LAST = HALF_WIDTH'(HALF_CYCLES - 1);
    localparam logic [LATCH_WIDTH-1:0] LATCH_LAST = LATCH_WIDTH'(LATCH_CYCLES - 1);

    initial begin
        if (CLK_HZ <= 0 || SHIFT_HZ <= 0 || LATCH_US <= 0 ||
            CLK_HZ < 2 * SHIFT_HZ || CLK_HZ % (2 * SHIFT_HZ) != 0)
            $fatal(1, "row_shift_controller requires an integral half-period divider");
    end

    typedef enum logic [2:0] {
        INIT_SETUP, IDLE, CLOCK_LOW, CLOCK_HIGH, LATCH_START, LATCH_HIGH
    } state_t;
    state_t state;
    logic [15:0] word_latched;
    logic [3:0]  bit_index;
    logic [HALF_WIDTH-1:0] half_count;
    logic [LATCH_WIDTH-1:0] latch_count;
    logic startup_transfer;

    assign busy = resetn && (state != IDLE);

    // Only clk clocks internal logic. sr_clk is a registered external pin.
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state            <= INIT_SETUP;
            word_latched     <= 16'hFFFF;
            bit_index        <= 4'd15;
            half_count       <= '0;
            latch_count      <= '0;
            startup_transfer <= 1'b1;
            sr_data          <= 1'b1;
            sr_clk           <= 1'b0;
            sr_latch         <= 1'b0;
            sr_oe_n          <= 1'b1;
            done_pulse       <= 1'b0;
            initialized      <= 1'b0;
        end else if (restart_safe) begin
            // Abort and soft reset take priority over a pending start.
            state            <= INIT_SETUP;
            startup_transfer <= 1'b1;
            sr_data          <= 1'b1;
            sr_clk           <= 1'b0;
            sr_latch         <= 1'b0;
            sr_oe_n          <= 1'b1;
            done_pulse       <= 1'b0;
            initialized      <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            case (state)
                INIT_SETUP: begin
                    word_latched     <= 16'hFFFF;
                    bit_index        <= 4'd15;
                    half_count       <= '0;
                    startup_transfer <= 1'b1;
                    sr_data          <= 1'b1;
                    sr_clk           <= 1'b0;
                    sr_latch         <= 1'b0;
                    sr_oe_n          <= 1'b1;
                    state            <= CLOCK_LOW;
                end
                IDLE: begin
                    if (start) begin
                        word_latched     <= mask;
                        bit_index        <= 4'd15;
                        half_count       <= '0;
                        startup_transfer <= 1'b0;
                        sr_data          <= mask[15];
                        state            <= CLOCK_LOW;
                    end
                end
                CLOCK_LOW: begin
                    if (half_count == HALF_LAST) begin
                        half_count <= '0;
                        sr_clk     <= 1'b1;
                        state      <= CLOCK_HIGH;
                    end else begin
                        half_count <= half_count + 1'b1;
                    end
                end
                CLOCK_HIGH: begin
                    if (half_count == HALF_LAST) begin
                        half_count <= '0;
                        sr_clk     <= 1'b0;
                        if (bit_index == 0) begin
                            state <= LATCH_START;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            sr_data   <= word_latched[bit_index - 1'b1];
                            state     <= CLOCK_LOW;
                        end
                    end else begin
                        half_count <= half_count + 1'b1;
                    end
                end
                LATCH_START: begin
                    sr_latch    <= 1'b1;
                    latch_count <= '0;
                    state       <= LATCH_HIGH;
                end
                LATCH_HIGH: begin
                    if (latch_count == LATCH_LAST) begin
                        sr_latch <= 1'b0;
                        state    <= IDLE;
                        if (startup_transfer) begin
                            initialized <= 1'b1;
                            sr_oe_n     <= 1'b0;
                        end else begin
                            done_pulse <= 1'b1;
                        end
                    end else begin
                        latch_count <= latch_count + 1'b1;
                    end
                end
                default: state <= INIT_SETUP;
            endcase
        end
    end
endmodule
