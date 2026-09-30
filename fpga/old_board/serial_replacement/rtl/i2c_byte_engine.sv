// Minimal open-drain I2C master for ADS1115 transactions. No clock stretching:
// the active Teensy ADS1115 path uses only SCL/SDA output and SDA input here.
module i2c_byte_engine #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000
) (
    input  logic       clk,
    input  logic       resetn,
    input  logic       start,
    input  logic       abort,
    input  logic [2:0] operation,
    input  logic [7:0] tx_byte,
    input  logic       sda_in,
    output logic       scl_drive_low,
    output logic       sda_drive_low,
    output logic [7:0] rx_byte,
    output logic       ack_received,
    output logic       busy,
    output logic       done_pulse
);
    localparam logic [2:0] OP_START = 3'd0, OP_STOP = 3'd1,
                           OP_WRITE = 3'd2, OP_READ_ACK = 3'd3,
                           OP_READ_NACK = 3'd4;
    // Round up so the open-drain bus never exceeds the requested rate.
    localparam integer Q_CYCLES = integer'((64'd1 * CLK_HZ +
        4 * I2C_HZ - 1) / (4 * I2C_HZ));
    localparam integer QW = (Q_CYCLES < 2) ? 1 : $clog2(Q_CYCLES);
    localparam logic [QW-1:0] Q_LAST = QW'(Q_CYCLES - 1);
    initial begin
        if (CLK_HZ <= 0 || I2C_HZ <= 0)
            $fatal(1, "I2C clock parameters must be positive");
    end

    typedef enum logic [4:0] {
        IDLE, START_A, START_B, START_C, START_D,
        STOP_A, STOP_B, STOP_C, STOP_D,
        W_SETUP, W_RISE, W_HIGH, W_FALL,
        ACK_SETUP, ACK_RISE, ACK_HIGH, ACK_FALL,
        R_SETUP, R_RISE, R_HIGH, R_FALL,
        RACK_SETUP, RACK_RISE, RACK_HIGH, RACK_FALL
    } state_t;
    state_t state;
    logic [QW-1:0] q_count;
    logic [7:0] tx_shift;
    logic [2:0] bit_index;
    logic nack_after_read;
    logic tick;
    assign tick = q_count == Q_LAST;
    assign busy = resetn && state != IDLE;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            q_count <= '0;
            tx_shift <= '0;
            bit_index <= '0;
            nack_after_read <= 1'b0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            rx_byte <= '0;
            ack_received <= 1'b0;
            done_pulse <= 1'b0;
        end else if (abort) begin
            state <= IDLE;
            q_count <= '0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            done_pulse <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            if (state == IDLE) begin
                q_count <= '0;
                if (start) begin
                    tx_shift <= tx_byte;
                    bit_index <= 3'd7;
                    nack_after_read <= operation == OP_READ_NACK;
                    if (operation == OP_START) state <= START_A;
                    else if (operation == OP_STOP) state <= STOP_A;
                    else if (operation == OP_WRITE) state <= W_SETUP;
                    else if (operation == OP_READ_ACK || operation == OP_READ_NACK) begin
                        rx_byte <= '0;
                        state <= R_SETUP;
                    end
                end
            end else if (!tick) q_count <= q_count + 1'b1;
            else begin
                q_count <= '0;
                case (state)
                    // A repeated START begins after an ACK with SCL low. Release
                    // SDA while SCL is low, then raise SCL before pulling SDA
                    // low. Releasing both together would look like a STOP.
                    START_A: begin scl_drive_low <= 1; sda_drive_low <= 0; state <= START_B; end
                    START_B: begin scl_drive_low <= 0; state <= START_C; end
                    START_C: begin sda_drive_low <= 1; state <= START_D; end
                    START_D: begin scl_drive_low <= 1; state <= IDLE; done_pulse <= 1; end
                    STOP_A: begin scl_drive_low <= 1; sda_drive_low <= 1; state <= STOP_B; end
                    STOP_B: begin scl_drive_low <= 0; state <= STOP_C; end
                    STOP_C: begin sda_drive_low <= 0; state <= STOP_D; end
                    STOP_D: begin state <= IDLE; done_pulse <= 1; end
                    W_SETUP: begin sda_drive_low <= !tx_shift[7]; state <= W_RISE; end
                    W_RISE: begin scl_drive_low <= 0; state <= W_HIGH; end
                    W_HIGH: state <= W_FALL;
                    W_FALL: begin
                        scl_drive_low <= 1;
                        if (bit_index == 0) state <= ACK_SETUP;
                        else begin
                            bit_index <= bit_index - 1'b1;
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            state <= W_SETUP;
                        end
                    end
                    ACK_SETUP: begin sda_drive_low <= 0; state <= ACK_RISE; end
                    ACK_RISE: begin scl_drive_low <= 0; state <= ACK_HIGH; end
                    ACK_HIGH: begin ack_received <= !sda_in; state <= ACK_FALL; end
                    ACK_FALL: begin
                        scl_drive_low <= 1;
                        state <= IDLE;
                        done_pulse <= 1;
                    end
                    R_SETUP: begin sda_drive_low <= 0; state <= R_RISE; end
                    R_RISE: begin scl_drive_low <= 0; state <= R_HIGH; end
                    R_HIGH: begin rx_byte <= {rx_byte[6:0], sda_in}; state <= R_FALL; end
                    R_FALL: begin
                        scl_drive_low <= 1;
                        if (bit_index == 0) state <= RACK_SETUP;
                        else begin bit_index <= bit_index - 1'b1; state <= R_SETUP; end
                    end
                    RACK_SETUP: begin sda_drive_low <= !nack_after_read; state <= RACK_RISE; end
                    RACK_RISE: begin scl_drive_low <= 0; state <= RACK_HIGH; end
                    RACK_HIGH: state <= RACK_FALL;
                    RACK_FALL: begin
                        scl_drive_low <= 1;
                        sda_drive_low <= 0;
                        state <= IDLE;
                        done_pulse <= 1;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
