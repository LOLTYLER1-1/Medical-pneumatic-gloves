`timescale 1ns / 1ps

module buzzer_ctrl #(
    parameter CLK_HZ      = 32'd100_000_000,
    parameter BEEP_FREQ_HZ = 32'd2
)(
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire trigger_i,
    output wire buzzer_o
);

    localparam HALF_PERIOD = CLK_HZ / BEEP_FREQ_HZ / 2;

    reg [25:0] counter;
    reg        tick;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            counter <= 26'd0;
            tick    <= 1'b0;
        end else if (!trigger_i) begin
            counter <= 26'd0;
            tick    <= 1'b0;
        end else if (counter >= HALF_PERIOD - 1) begin
            counter <= 26'd0;
            tick    <= ~tick;
        end else begin
            counter <= counter + 1'b1;
        end
    end

    assign buzzer_o = trigger_i & tick;

endmodule
