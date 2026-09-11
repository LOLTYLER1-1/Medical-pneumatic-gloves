//=============================================================================
// File        : glove_fsm_annotated.v   ★教学版★
// 类比: Arduino 主程序里 switch(state) { case A: ...; break; } 的硬件版
//
// 本版本为 "免焊接简化版": 砍掉 V1 充气阀, 气路变为
//   气泵 → 手套 → V2(泄气阀) → 大气
//
// Rev 2026-08-02 修订:
//   ★ 压力单位全链路统一为 0.01kPa (5000 = 50.00kPa)
//   ★ GRIP→HOLD 判定定为 "pressure >= setpoint" (充到目标即停)
//   ★ 新增回差 HYST=200 (2kPa): HOLD 中压力跌破 setpoint-2kPa 才补气,
//     防止在设定值附近 ±0.01kPa 抖动导致泵每个周期都启停
//   ★ 注意: setpoint_i 必须大于 HYST (PS 端默认写 5000)
//=============================================================================

`timescale 1ns / 1ps

module glove_fsm #(
    parameter PRESSURE_MIN = 16'd100,                   // 1.00 kPa, 低于此视为已泄气
    parameter HYST         = 16'd200                    // 2.00 kPa, HOLD 保压回差
)(
    input  wire        clk_i,                           // 100 MHz
    input  wire        rst_n_i,                         // 同步复位
    input  wire        grip_req_i,                      // 抓握请求(来自触摸/PS)
    input  wire        release_req_i,                   // 松手请求
    input  wire        emerg_i,                         // 紧急停止(急停按键 或 传感器故障)
    input  wire [15:0] pressure_i,                      // 当前压力, 单位 0.01kPa
    input  wire [15:0] setpoint_i,                      // 目标压力, 单位 0.01kPa (来自 PS)
    output reg  [2:0]  state_o,                         // 当前状态码
    output reg         pump_o,                          // 气泵驱动
    output reg         v2_o                             // 泄气阀驱动(1=通电=关闭密闭)
);

    // === 状态编码 ===
    localparam IDLE      = 3'd0;                        // 待机
    localparam GRIP      = 3'd1;                        // 抓握: 充气中
    localparam HOLD      = 3'd2;                        // 保持: 已达目标压力
    localparam RELEASE   = 3'd3;                        // 松手: 泄气中
    localparam EMERGENCY = 3'd4;                        // 急停

    reg [2:0] next_state;

    // === 组合逻辑: 计算下一状态 ===
    always @(*) begin
        next_state = state_o;                           // 默认保持
        if (emerg_i) begin
            next_state = EMERGENCY;                     // 急停优先
        end else begin
            case (state_o)
                IDLE: if (grip_req_i)
                          next_state = GRIP;
                GRIP: if (release_req_i)
                          next_state = RELEASE;
                      else if (pressure_i >= setpoint_i)
                          next_state = HOLD;            // 充到目标压力即停泵
                HOLD: if (release_req_i)
                          next_state = RELEASE;
                      else if (grip_req_i && pressure_i < setpoint_i - HYST)
                          next_state = GRIP;            // 掉压超过回差 → 补气
                RELEASE: if (grip_req_i)
                             next_state = GRIP;
                         else if (pressure_i <= PRESSURE_MIN)
                             next_state = IDLE;
                EMERGENCY: if (pressure_i <= PRESSURE_MIN)
                               next_state = IDLE;
                default: next_state = IDLE;
            endcase
        end
    end

    // === 时序逻辑: 锁存状态 ===
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) state_o <= IDLE;
        else          state_o <= next_state;
    end

    // === 状态 → 输出 (Moore 型) ===
    // V2 是常开型 NO: 输出 0 时阀门开(自动泄气), 输出 1 时阀门关闭(密闭)
    // 充气逻辑: pump 开 + V2 关 = 气体从泵推入手套, 不能从 V2 逸出 → 压力上升
    always @(*) begin
        case (state_o)
            IDLE     : begin pump_o = 1'b0; v2_o = 1'b0; end  // 全失电 = 通大气
            GRIP     : begin pump_o = 1'b1; v2_o = 1'b1; end  // 泵开 + V2 关 = 充气
            HOLD     : begin pump_o = 1'b0; v2_o = 1'b1; end  // 停泵 + V2 关 = 密闭
            RELEASE  : begin pump_o = 1'b0; v2_o = 1'b0; end  // V2 失电 = 自动泄气
            EMERGENCY: begin pump_o = 1'b0; v2_o = 1'b0; end  // 全失电 = 完全安全
            default  : begin pump_o = 1'b0; v2_o = 1'b0; end
        endcase
    end

endmodule
