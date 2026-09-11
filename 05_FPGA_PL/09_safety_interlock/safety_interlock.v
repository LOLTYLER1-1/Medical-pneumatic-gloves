`timescale 1ns / 1ps

module safety_interlock #(
    parameter PRESSURE_LIMIT = 16'd8000      // 80.00 kPa (× 100)
)(
    input  wire [15:0] pressure_i,
    input  wire        pump_in_i,
    input  wire        v2_in_i,

    output wire        pump_out_o,
    output wire        v2_out_o,
    output wire        trigger_o
);

    assign trigger_o  = (pressure_i >= PRESSURE_LIMIT);
    assign pump_out_o = trigger_o ? 1'b0 : pump_in_i;
    assign v2_out_o   = trigger_o ? 1'b0 : v2_in_i;

endmodule
