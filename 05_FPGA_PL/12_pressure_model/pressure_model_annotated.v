`timescale 1ns / 1ps

//=============================================================================
// File        : pressure_model_annotated.v   ★教学版（不要加入工程综合）★
// 仿真压力源 (植物模型): 真实气压传感器缺席/损坏时的演示替身。
//
// 类比: Arduino 里没有温度传感器时, 用"加热时长×功率"估算水温做演示。
//
// 模型规则 (与 glove_fsm 输出约定一致):
//   valve_i=0 (阀开, RELEASE/IDLE/EMERGENCY): 快速泄气 (100.00kPa/1s)
//   valve_i=1 且 pump_i=1 (阀闭+泵开, GRIP):  充气 (50.00kPa/4s)
//   valve_i=1 且 pump_i=0 (阀闭保压, HOLD):   缓慢泄漏 (1.00kPa/s)
//     —— 泄漏让 HOLD 期压力缓降, 可演示 FSM 回差补气 (跌 2kPa 后重新 GRIP)
//
// ★ 仅用于演示/开发: 开环估算, 不能反映真实气压, 严禁用于人体。
//   真实传感器到位后, 顶层 SIM_PRESSURE 参数改 0 即切回闭环。
//=============================================================================
module pressure_model #(
    parameter CLK_FREQ_HZ         = 32'd100_000_000,
    parameter INC_X100KPA_PER_S   = 16'd1250,    // 充气速率: 50.00kPa/4s
    parameter DEC_X100KPA_PER_S   = 16'd10000,   // 泄气速率: 100.00kPa/1s
    parameter LEAK_X100KPA_PER_S  = 16'd100      // 保压泄漏: 1.00kPa/s
)(
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        pump_i,       // 实际泵输出 (安全联锁之后)
    input  wire        valve_i,      // 实际阀输出: 0=开(泄气) 1=闭(密封)
    output wire [15:0] pressure_o    // 模型气压, 单位 0.01kPa
);

    // === 1ms 节拍发生器: 100MHz / 100000 = 1kHz ===
    localparam MS_MAX = CLK_FREQ_HZ / 1000;
    reg [31:0] ms_cnt;
    reg        ms_tick;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ms_cnt  <= 32'd0;
            ms_tick <= 1'b0;
        end else if (ms_cnt >= MS_MAX - 1) begin
            ms_cnt  <= 32'd0;
            ms_tick <= 1'b1;             // 每 1ms 一个脉冲
        end else begin
            ms_cnt  <= ms_cnt + 32'd1;
            ms_tick <= 1'b0;
        end
    end

    // === Q8 定点压力 (0.01kPa × 256): 每 1ms 加/减一个固定步长 ===
    // 为什么用 Q8: 1250/1000=1.25 不是整数, 放大 256 倍后 320 是整数,
    // 避免四舍五入累积误差; 输出时右移 8 位取整。
    localparam P_MAX_Q8  = 24'd9999 * 256;                    // 上限 99.99kPa
    localparam INC_Q8_MS  = INC_X100KPA_PER_S  * 256 / 1000;  // 320  ≈1.25/ms
    localparam DEC_Q8_MS  = DEC_X100KPA_PER_S  * 256 / 1000;  // 2560 =10/ms
    localparam LEAK_Q8_MS = LEAK_X100KPA_PER_S * 256 / 1000;  // 25   ≈0.1/ms

    reg [23:0] p_q8;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            p_q8 <= 24'd0;
        end else if (ms_tick) begin
            if (!valve_i) begin
                // 阀开: 快速泄气, 下钳 0 (不能为负)
                p_q8 <= (p_q8 > DEC_Q8_MS) ? p_q8 - DEC_Q8_MS : 24'd0;
            end else if (pump_i) begin
                // 阀闭泵开: 充气, 上钳 99.99kPa
                p_q8 <= (p_q8 < P_MAX_Q8 - INC_Q8_MS) ? p_q8 + INC_Q8_MS : P_MAX_Q8;
            end else begin
                // 阀闭泵停: 缓慢泄漏, 下钳 0
                p_q8 <= (p_q8 > LEAK_Q8_MS) ? p_q8 - LEAK_Q8_MS : 24'd0;
            end
        end
    end

    assign pressure_o = p_q8[23:8];   // 右移 8 位去小数, 输出 0.01kPa 整数

endmodule
