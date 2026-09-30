`timescale 1ns/1ps
// Independent, deliberately small ADS1115 I2C model for the active protocol.
module ads1115_i2c_model (
    input wire scl,
    input wire sda,
    output logic sda_drive_low = 0,
    output logic [15:0] last_config = 0,
    output integer config_writes = 0,
    output integer config_reads = 0,
    output integer conversion_reads = 0
);
    integer mode = 0; // 0 idle, 1 RX, 2 ACK prep, 3 ACK clock, 4 TX, 5 master ACK, 6 ACK fall, 7 wait STOP
    integer bit_count = 0, tx_bit = 7, tx_byte_index = 0;
    logic [7:0] rx_shift = 0, tx_byte = 0, config_high = 0;
    logic [15:0] transmit_word = 0;
    logic [7:0] pointer = 0;
    logic expect_address = 1, read_mode = 0, ack_this = 1;
    integer write_stage = 0, remaining_busy = 0;
    integer start_count = 0, stop_count = 0;
    integer ready_after_polls = 2;
    logic force_never_ready = 0;
    logic nack_next_address = 0;
    logic [15:0] conversion_word = 16'h1234;

    always @(negedge sda) if (scl) begin
        start_count = start_count + 1;
        mode = 1;
        bit_count = 0;
        rx_shift = 0;
        expect_address = 1;
        sda_drive_low = 0;
    end
    always @(posedge sda) if (scl) begin
        stop_count = stop_count + 1;
        mode = 0;
        sda_drive_low = 0;
    end

    task automatic decode_byte(input logic [7:0] value);
        begin
            ack_this = 1;
            if (expect_address) begin
                expect_address = 0;
                if (value[7:1] != 7'h48 || nack_next_address) begin
                    ack_this = 0;
                    nack_next_address = 0;
                end else begin
                    read_mode = value[0];
                    if (!read_mode) write_stage = 0;
                    else begin
                        tx_byte_index = 0;
                        if (pointer == 8'h01) begin
                            config_reads = config_reads + 1;
                            if (force_never_ready || remaining_busy > 0) begin
                                transmit_word = last_config & 16'h7FFF;
                                if (!force_never_ready) remaining_busy = remaining_busy - 1;
                            end else transmit_word = last_config | 16'h8000;
                        end else begin
                            conversion_reads = conversion_reads + 1;
                            transmit_word = conversion_word;
                        end
                    end
                end
            end else if (!read_mode) begin
                if (write_stage == 0) begin
                    pointer = value;
                    write_stage = 1;
                end else if (pointer == 8'h01 && write_stage == 1) begin
                    config_high = value;
                    write_stage = 2;
                end else if (pointer == 8'h01 && write_stage == 2) begin
                    last_config = {config_high, value};
                    config_writes = config_writes + 1;
                    remaining_busy = ready_after_polls;
                    write_stage = 1;
                end
            end
        end
    endtask

    always @(posedge scl) begin
        if (mode == 1) begin
            rx_shift = {rx_shift[6:0], sda};
            bit_count = bit_count + 1;
            if (bit_count == 8) begin
                decode_byte(rx_shift);
                mode = 2;
            end
        end else if (mode == 5) begin
            ack_this = !sda;
            mode = 6;
        end
    end

    always @(negedge scl) begin
        if (mode == 2) begin
            sda_drive_low = ack_this;
            mode = 3;
        end else if (mode == 3) begin
            sda_drive_low = 0;
            if (!ack_this) mode = 7;
            else if (read_mode) begin
                tx_byte = transmit_word[15:8];
                tx_bit = 7;
                sda_drive_low = !tx_byte[tx_bit];
                mode = 4;
            end else begin
                bit_count = 0;
                rx_shift = 0;
                mode = 1;
            end
        end else if (mode == 4) begin
            if (tx_bit == 0) begin
                sda_drive_low = 0;
                mode = 5;
            end else begin
                tx_bit = tx_bit - 1;
                sda_drive_low = !tx_byte[tx_bit];
            end
        end else if (mode == 6) begin
            if (ack_this && tx_byte_index == 0) begin
                tx_byte_index = 1;
                tx_byte = transmit_word[7:0];
                tx_bit = 7;
                sda_drive_low = !tx_byte[tx_bit];
                mode = 4;
            end else mode = 7;
        end
    end
endmodule
