`timescale 1ns / 1ps

module axi_lite_reg (
    input  wire        clk_i,
    input  wire        rst_n_i,

    input  wire [15:0] pressure_kpa_i,
    input  wire [2:0]  fsm_state_i,
    input  wire        safety_trigger_i,

    output reg  [15:0] pressure_kpa_o,
    output reg  [2:0]  fsm_state_o,
    output reg         safety_trigger_o
);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pressure_kpa_o   <= 16'd0;
            fsm_state_o      <= 3'd0;
            safety_trigger_o <= 1'b0;
        end else begin
            pressure_kpa_o   <= pressure_kpa_i;
            fsm_state_o      <= fsm_state_i;
            safety_trigger_o <= safety_trigger_i;
        end
    end

endmodule
