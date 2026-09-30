// Active Teensy ADS1115 read: single-shot write, OS polling, conversion read.
// Channel is one-based (1..4), result is signed two's-complement raw counts.
module ads1115_controller #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000,
    parameter integer POLL_US = 50,
    parameter integer TIMEOUT_US = 10_000
) (
    input  logic        clk,
    input  logic        resetn,
    input  logic        start,
    input  logic        abort,
    input  logic        probe,
    input  logic [2:0]  channel,
    input  logic        sda_in,
    output logic        scl_drive_low,
    output logic        sda_drive_low,
    output logic signed [15:0] raw_result,
    output logic        busy,
    output logic        done_pulse,
    output logic        valid,
    output logic [7:0]  error_code
);
    localparam logic [2:0] OP_START = 3'd0, OP_STOP = 3'd1,
                           OP_WRITE = 3'd2, OP_READ_ACK = 3'd3,
                           OP_READ_NACK = 3'd4;
    localparam logic [1:0] PH_CONFIG = 0, PH_POLL = 1, PH_RESULT = 2;
    localparam logic [31:0] POLL_CYCLES =
        32'(((64'd1 * CLK_HZ * POLL_US) + 999_999) / 1_000_000);
    localparam logic [31:0] TIMEOUT_CYCLES =
        32'(((64'd1 * CLK_HZ * TIMEOUT_US) + 999_999) / 1_000_000);
    localparam logic [7:0] ERR_NACK = 8'h10, ERR_TIMEOUT = 8'h11,
                           ERR_CHANNEL = 8'h12;

    typedef enum logic [2:0] {
        IDLE, ISSUE, WAIT_BYTE, WAIT_INTERVAL, FAIL_STOP_ISSUE, FAIL_STOP_WAIT
    } state_t;
    state_t state;
    logic [1:0] phase;
    logic [2:0] step;
    logic [15:0] config_word;
    logic [7:0] high_byte, low_byte;
    logic poll_ready;
    logic [31:0] elapsed_cycles, interval_count;
    logic eng_start, eng_done, eng_ack, eng_busy;
    logic [2:0] eng_op;
    logic [7:0] eng_tx, eng_rx;
    logic retry_poll;
    logic probe_mode;
    assign busy = resetn && state != IDLE;
    assign eng_start = state == ISSUE || state == FAIL_STOP_ISSUE;

    always @* begin
        eng_op = OP_START;
        eng_tx = 8'h00;
        if (state == FAIL_STOP_ISSUE) eng_op = OP_STOP;
        else if (phase == PH_CONFIG) begin
            case (step)
                3'd0: eng_op = OP_START;
                3'd1: begin eng_op = OP_WRITE; eng_tx = 8'h90; end
                3'd2: begin eng_op = OP_WRITE; eng_tx = 8'h01; end
                3'd3: begin eng_op = OP_WRITE; eng_tx = config_word[15:8]; end
                3'd4: begin eng_op = OP_WRITE; eng_tx = config_word[7:0]; end
                default: eng_op = OP_STOP;
            endcase
        end else begin
            case (step)
                3'd0: eng_op = OP_START;
                3'd1: begin eng_op = OP_WRITE; eng_tx = 8'h90; end
                3'd2: begin eng_op = OP_WRITE; eng_tx = phase == PH_POLL ? 8'h01 : 8'h00; end
                3'd3: eng_op = OP_START;
                3'd4: begin eng_op = OP_WRITE; eng_tx = 8'h91; end
                3'd5: eng_op = OP_READ_ACK;
                3'd6: eng_op = OP_READ_NACK;
                default: eng_op = OP_STOP;
            endcase
        end
    end

    i2c_byte_engine #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ)) u_i2c (
        .clk, .resetn, .start(eng_start), .abort, .operation(eng_op),
        .tx_byte(eng_tx), .sda_in, .scl_drive_low, .sda_drive_low,
        .rx_byte(eng_rx), .ack_received(eng_ack), .busy(eng_busy),
        .done_pulse(eng_done)
    );

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            phase <= PH_CONFIG;
            step <= 0;
            config_word <= 0;
            high_byte <= 0;
            low_byte <= 0;
            poll_ready <= 0;
            elapsed_cycles <= 0;
            interval_count <= 0;
            raw_result <= 0;
            done_pulse <= 0;
            valid <= 0;
            error_code <= 0;
            retry_poll <= 0;
            probe_mode <= 0;
        end else if (abort) begin
            state <= IDLE;
            done_pulse <= 0;
            valid <= 0;
            error_code <= 0;
        end else begin
            done_pulse <= 0;
            if (phase == PH_POLL && state != IDLE && elapsed_cycles != 32'hFFFF_FFFF)
                elapsed_cycles <= elapsed_cycles + 1'b1;
            case (state)
                IDLE: if (start) begin
                    valid <= 0;
                    error_code <= 0;
                    elapsed_cycles <= 0;
                    probe_mode <= probe;
                    phase <= probe ? PH_POLL : PH_CONFIG;
                    step <= 0;
                    case (channel)
                        3'd1: config_word <= 16'hC3E3;
                        3'd2: config_word <= 16'hD3E3;
                        3'd3: config_word <= 16'hE3E3;
                        3'd4: config_word <= 16'hF3E3;
                        default: config_word <= 16'h0000;
                    endcase
                    if (!probe && (channel < 1 || channel > 4)) begin
                        error_code <= ERR_CHANNEL;
                        done_pulse <= 1;
                    end else state <= ISSUE;
                end
                ISSUE: state <= WAIT_BYTE;
                WAIT_BYTE: if (eng_done) begin
                    if (eng_op == OP_WRITE && !eng_ack) begin
                        retry_poll <= phase == PH_POLL && !probe_mode;
                        error_code <= ERR_NACK;
                        state <= FAIL_STOP_ISSUE;
                    end else begin
                        if (step == 3'd5 && phase != PH_CONFIG) begin
                            high_byte <= eng_rx;
                            if (phase == PH_POLL) poll_ready <= eng_rx[7];
                        end
                        if (step == 3'd6 && phase != PH_CONFIG) low_byte <= eng_rx;
                        if ((phase == PH_CONFIG && step == 3'd5) ||
                            (phase != PH_CONFIG && step == 3'd7)) begin
                            if (phase == PH_CONFIG) begin
                                phase <= PH_POLL;
                                step <= 0;
                                elapsed_cycles <= 0;
                                state <= ISSUE;
                            end else if (phase == PH_POLL) begin
                                if (probe_mode) begin
                                    raw_result <= {high_byte, low_byte};
                                    valid <= 1;
                                    done_pulse <= 1;
                                    state <= IDLE;
                                end else if (poll_ready) begin
                                    phase <= PH_RESULT;
                                    step <= 0;
                                    error_code <= 0;
                                    state <= ISSUE;
                                end else if (elapsed_cycles >= TIMEOUT_CYCLES) begin
                                    error_code <= ERR_TIMEOUT;
                                    done_pulse <= 1;
                                    state <= IDLE;
                                end else begin
                                    interval_count <= POLL_CYCLES;
                                    state <= WAIT_INTERVAL;
                                end
                            end else begin
                                raw_result <= {high_byte, low_byte};
                                valid <= 1;
                                done_pulse <= 1;
                                state <= IDLE;
                            end
                        end else begin
                            step <= step + 1'b1;
                            state <= ISSUE;
                        end
                    end
                end
                WAIT_INTERVAL: if (interval_count == 0) begin
                    step <= 0;
                    poll_ready <= 0;
                    state <= ISSUE;
                end else interval_count <= interval_count - 1'b1;
                FAIL_STOP_ISSUE: state <= FAIL_STOP_WAIT;
                FAIL_STOP_WAIT: if (eng_done) begin
                    if (retry_poll && elapsed_cycles < TIMEOUT_CYCLES) begin
                        interval_count <= POLL_CYCLES;
                        poll_ready <= 0;
                        error_code <= 0;
                        state <= WAIT_INTERVAL;
                    end else begin
                        if (retry_poll) error_code <= ERR_TIMEOUT;
                        done_pulse <= 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
