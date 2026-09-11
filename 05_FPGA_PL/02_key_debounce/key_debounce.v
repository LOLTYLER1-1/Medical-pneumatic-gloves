
`timescale 1ns / 1ps

module key_debounce #(
    parameter CLK_FREQ_HZ   = 32'd100_000_000,
    parameter DEBOUNCE_MS   = 32'd20,
    parameter DEBOUNCE_MAX  = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS
)(
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire key_raw_i,

    output reg  key_clean_o
);

    reg key_sync_1, key_sync_2;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            key_sync_1 <= 1'b1;
            key_sync_2 <= 1'b1;
        end else begin
            key_sync_1 <= key_raw_i;
            key_sync_2 <= key_sync_1;
        end
    end

    reg [31:0] cnt;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt         <= 32'd0;
            key_clean_o <= 1'b1;
        end else if (key_sync_2 != key_clean_o) begin
            if (cnt >= DEBOUNCE_MAX - 1) begin
                cnt         <= 32'd0;
                key_clean_o <= key_sync_2;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end else begin
            cnt <= 32'd0;
        end
    end

endmodule
