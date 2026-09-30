`timescale 1ns/1ps
module ad5689_spi_monitor #(
    parameter integer PERIOD_NS = 400
) (
    input wire cs_n,
    input wire sclk,
    input wire mosi,
    output logic [23:0] last_frame = 0,
    output integer frame_count = 0
);
    logic [23:0] shifted = 0;
    integer bits = 0;
    time last_mosi_change = 0;
    time last_fall = 0;
    always @(mosi) last_mosi_change = $time;
    // Mode 1: the DAC samples each falling SCLK edge.
    always @(negedge sclk) if (!cs_n) begin
        if ($time - last_mosi_change == 0) $fatal(1, "DAC MOSI changed at sample edge");
        if (bits != 0 && $time-last_fall != PERIOD_NS)
            $fatal(1, "DAC SCLK period was %0t, expected %0d ns",
                   $time-last_fall, PERIOD_NS);
        last_fall = $time;
        shifted = {shifted[22:0], mosi};
        bits = bits + 1;
    end
    always @(posedge cs_n) if (bits != 0) begin
        if (bits != 24 || sclk !== 1'b0)
            $fatal(1, "DAC frame had %0d bits or bad idle clock", bits);
        last_frame = shifted;
        frame_count = frame_count + 1;
        bits = 0;
        last_fall = 0;
        shifted = 0;
    end
endmodule
