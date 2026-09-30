// AD5689 transactions used by the active Teensy firmware. SPI mode 1:
// SCLK idles low, MOSI changes on rising edges and is sampled on falling edges.
module ad5689_controller #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SPI_HZ = 30_000_000
) (
    input  logic        clk,
    input  logic        resetn,
    input  logic        start,
    input  logic        abort,
    input  logic [2:0]  operation,
    input  logic [15:0] code,
    output logic        sclk,
    output logic        mosi,
    output logic        cs_n,
    output logic        busy,
    output logic        done_pulse
);
    localparam logic [2:0] SOFT_RESET = 3'd0, REF_ON = 3'd1,
                           ZERO_A = 3'd2, ZERO_B = 3'd3,
                           WRITE_A = 3'd4, WRITE_B = 3'd5;
    // Round up so the generated SPI clock never exceeds the requested rate.
    localparam integer HALF_CYCLES = integer'((64'd1 * CLK_HZ +
        2 * SPI_HZ - 1) / (2 * SPI_HZ));
    localparam integer CW = (HALF_CYCLES < 2) ? 1 : $clog2(HALF_CYCLES);
    localparam logic [CW-1:0] HALF_LAST = CW'(HALF_CYCLES - 1);
    initial begin
        if (CLK_HZ <= 0 || SPI_HZ <= 0)
            $fatal(1, "AD5689 clock parameters must be positive");
    end

    function automatic logic [23:0] make_frame(input logic [2:0] op,
                                                input logic [15:0] value);
        case (op)
            SOFT_RESET: make_frame = 24'h60_0000;
            REF_ON:     make_frame = 24'h70_0000;
            ZERO_A:     make_frame = 24'h31_0000;
            ZERO_B:     make_frame = 24'h38_0000;
            WRITE_A:    make_frame = {8'h31, value};
            WRITE_B:    make_frame = {8'h38, value};
            default:    make_frame = 24'h00_0000;
        endcase
    endfunction

    typedef enum logic [2:0] {IDLE, LOW_HALF, HIGH_HALF, RELEASE_CS} state_t;
    state_t state;
    logic [23:0] frame;
    logic [4:0] bit_index;
    logic [CW-1:0] half_count;
    assign busy = resetn && state != IDLE;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            frame <= '0;
            bit_index <= '0;
            half_count <= '0;
            sclk <= 1'b0;
            mosi <= 1'b0;
            cs_n <= 1'b1;
            done_pulse <= 1'b0;
        end else if (abort) begin
            state <= IDLE;
            sclk <= 1'b0;
            mosi <= 1'b0;
            cs_n <= 1'b1;
            done_pulse <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    frame <= make_frame(operation, code);
                    bit_index <= 5'd23;
                    half_count <= '0;
                    cs_n <= 1'b0;
                    state <= LOW_HALF;
                end
                LOW_HALF: if (half_count == HALF_LAST) begin
                    half_count <= '0;
                    mosi <= frame[bit_index];
                    sclk <= 1'b1;
                    state <= HIGH_HALF;
                end else half_count <= half_count + 1'b1;
                HIGH_HALF: if (half_count == HALF_LAST) begin
                    half_count <= '0;
                    sclk <= 1'b0;
                    if (bit_index == 0) state <= RELEASE_CS;
                    else begin
                        bit_index <= bit_index - 1'b1;
                        state <= LOW_HALF;
                    end
                end else half_count <= half_count + 1'b1;
                RELEASE_CS: begin
                    cs_n <= 1'b1;
                    mosi <= 1'b0;
                    done_pulse <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
