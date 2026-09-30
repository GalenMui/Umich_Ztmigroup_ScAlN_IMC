// A count of N holds pulse_out high for exactly N clk cycles. N=0 completes
// immediately without a pulse. Requests while busy are ignored by this engine;
// the top-level arbiter reports command conflicts.
module cycle_timer (
    input  logic        clk,
    input  logic        resetn,
    input  logic        start,
    input  logic        abort,
    input  logic [31:0] cycles,
    output logic        pulse_out,
    output logic        busy,
    output logic        done_pulse
);
    logic [31:0] remaining;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            remaining <= 32'd0;
            pulse_out <= 1'b0;
            busy <= 1'b0;
            done_pulse <= 1'b0;
        end else if (abort) begin
            remaining <= 32'd0;
            pulse_out <= 1'b0;
            busy <= 1'b0;
            done_pulse <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            if (busy) begin
                if (remaining == 32'd1) begin
                    remaining <= 32'd0;
                    pulse_out <= 1'b0;
                    busy <= 1'b0;
                    done_pulse <= 1'b1;
                end else remaining <= remaining - 1'b1;
            end else if (start) begin
                if (cycles == 0) done_pulse <= 1'b1;
                else begin
                    remaining <= cycles;
                    pulse_out <= 1'b1;
                    busy <= 1'b1;
                end
            end
        end
    end
endmodule
