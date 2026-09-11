`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// glove_fsm.v   Rev 2026-08-02
// 修订: 压力单位统一为 0.01kPa 后, GRIP->HOLD 判定由 ">= setpoint+HYST" 改为
//       ">= setpoint" (充到目标即停); HOLD 回差 HYST 由 20(0.2kPa) 加大到
//       200(2kPa), 防止设定值附近泵频繁启停。setpoint_i 必须大于 HYST。
//-----------------------------------------------------------------------------
module glove_fsm #(
    parameter PRESSURE_MIN = 16'd100,   /* 1.00 kPa: 低于此值视为已泄尽 */
    parameter HYST          = 16'd200   /* 2.00 kPa: HOLD 保压回差 */
)(
    input  wire        clk_i,
    input  wire        rst_n_i,

    input  wire        grip_req_i,
    input  wire        release_req_i,
    input  wire        emerg_i,
    input  wire [15:0] pressure_i,      /* 当前压力, 单位 0.01kPa */
    input  wire [15:0] setpoint_i,      /* 目标压力, 单位 0.01kPa (来自 PS) */

    output reg  [2:0]  state_o,
    output reg         pump_o,
    output reg         v2_o
);

    localparam IDLE      = 3'd0;
    localparam GRIP      = 3'd1;
    localparam HOLD      = 3'd2;
    localparam RELEASE   = 3'd3;
    localparam EMERGENCY = 3'd4;

    reg [2:0] next_state;

    always @(*) begin
        next_state = state_o;
        if (emerg_i) begin
            next_state = EMERGENCY;
        end else begin
            case (state_o)
                IDLE     : if (grip_req_i)                       next_state = GRIP;
                GRIP     : if (release_req_i)                    next_state = RELEASE;
                           else if (pressure_i >= setpoint_i)    next_state = HOLD;
                HOLD     : if (release_req_i)                    next_state = RELEASE;
                           else if (grip_req_i &&
                                    pressure_i < setpoint_i - HYST) next_state = GRIP;
                RELEASE  : if (grip_req_i)                       next_state = GRIP;
                           else if (pressure_i <= PRESSURE_MIN)  next_state = IDLE;
                EMERGENCY: if (pressure_i <= PRESSURE_MIN)       next_state = IDLE;
                default  :                                       next_state = IDLE;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) state_o <= IDLE;
        else          state_o <= next_state;
    end

    always @(*) begin
        case (state_o)
            IDLE     : begin pump_o = 1'b0; v2_o = 1'b0; end
            GRIP     : begin pump_o = 1'b1; v2_o = 1'b1; end
            HOLD     : begin pump_o = 1'b0; v2_o = 1'b1; end
            RELEASE  : begin pump_o = 1'b0; v2_o = 1'b0; end
            EMERGENCY: begin pump_o = 1'b0; v2_o = 1'b0; end
            default  : begin pump_o = 1'b0; v2_o = 1'b0; end
        endcase
    end

endmodule