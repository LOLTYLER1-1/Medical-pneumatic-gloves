//=============================================================================
// File        : safety_interlock_annotated.v   ★教学版★
// 类比: 物理保险丝/继电器联锁, 不依赖 CPU 或时钟
// 关键: 纯组合逻辑, 0 时钟延迟响应, 是最后一道防线
//
// 本版本免焊接简化: 砍掉 V1, 只剩 pump + V2 两路输出
//=============================================================================

`timescale 1ns / 1ps

module safety_interlock #(
    parameter PRESSURE_LIMIT = 16'd8000                 // 80.00 kPa 硬上限
)(
    input  wire [15:0] pressure_i,                      // 当前压力 (kPa*100)
    input  wire        pump_in_i,                       // 状态机给的气泵驱动
    input  wire        v2_in_i,                         // 状态机给的 V2

    output wire        pump_out_o,                      // 实际输出气泵驱动
    output wire        v2_out_o,                        // 实际输出 V2
    output wire        trigger_o                        // 1=已触发硬件安全切断
);

    // 触发条件: 压力 >= 80.00 kPa
    assign trigger_o = (pressure_i >= PRESSURE_LIMIT);

    // 超限强切:
    //   pump = 0 (停泵)
    //   V2   = 0 (失电 = 阀开 = 泄气)
    // 未超限: 透传
    assign pump_out_o = trigger_o ? 1'b0 : pump_in_i;
    assign v2_out_o   = trigger_o ? 1'b0 : v2_in_i;

endmodule
