//=============================================================================
// File        : axi_lite_reg_annotated.v   ★教学版★
// 类比: Arduino 中 Serial.print() 让上位机看 → 这里是 PL 让 PS(ARM)看
//       但比 UART 快多了, 因为 EMIO 是 PS GPIO 的外部映射, 直接是寄存器读写
//
// 为什么用一级寄存器隔离而非 wire 直通:
//   - 隔离 PL 内部时钟域, 让 PS 读到的是稳定值
//   - 避免毛刺(glitch)直接传到 PS GPIO
//=============================================================================

`timescale 1ns / 1ps

module axi_lite_reg (
    input  wire        clk_i,                           // 100 MHz
    input  wire        rst_n_i,                         // 同步复位

    // ---- PL 内部送进来的状态 ----
    input  wire [15:0] pressure_kpa_i,                  // 压力(kPa*100)
    input  wire [2:0]  fsm_state_i,                     // 状态机码
    input  wire        safety_trigger_i,                // 硬件安全触发

    // ---- 经 EMIO 给 PS 端读 ----
    output reg  [15:0] pressure_kpa_o,
    output reg  [2:0]  fsm_state_o,
    output reg         safety_trigger_o
);

    // 一级寄存器锁存(简单稳定即可, 不引入额外延迟)
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
