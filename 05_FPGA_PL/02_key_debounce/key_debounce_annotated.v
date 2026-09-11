//=============================================================================
// File        : key_debounce_annotated.v   ★教学版★
// 类比: Arduino 中 digitalRead 后 delay(20) 再读一次
//       不同的是这里用计数器代替 delay, 不会阻塞 CPU
//=============================================================================

`timescale 1ns / 1ps

module key_debounce #(
    parameter CLK_FREQ_HZ   = 32'd100_000_000,          // 时钟频率 100 MHz
    parameter DEBOUNCE_MS   = 32'd20,                   // 消抖时间 20 ms
    parameter DEBOUNCE_MAX  = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS  // 需要计的时钟数 = 2,000,000
)(
    input  wire clk_i,                                  // 100 MHz 主时钟
    input  wire rst_n_i,                                // 同步复位(低有效)
    input  wire key_raw_i,                              // 原始按键信号(从 IO 进来, 含抖动)

    output reg  key_clean_o                             // 消抖后的稳定信号
);

    // === 第 1 级: 两级同步器, 消除亚稳态 ===
    // 按键来自外部异步信号, 直接进逻辑会引发亚稳态
    reg key_sync_1, key_sync_2;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            key_sync_1 <= 1'b1;                         // 按键松开为高(上拉)
            key_sync_2 <= 1'b1;
        end else begin
            key_sync_1 <= key_raw_i;                    // 1 级
            key_sync_2 <= key_sync_1;                   // 2 级 (现在与时钟同步了)
        end
    end

    // === 第 2 级: 计数器消抖 ===
    // 思路: 状态稳定保持 20ms = 2,000,000 个时钟周期, 才认可
    reg [31:0] cnt;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt         <= 32'd0;
            key_clean_o <= 1'b1;                        // 复位状态: 假设按键松开
        end else if (key_sync_2 != key_clean_o) begin   // 输入与当前认可值不同 → 开始计时
            if (cnt >= DEBOUNCE_MAX - 1) begin          // 已稳定 20 ms
                cnt         <= 32'd0;                   // 计数器清零
                key_clean_o <= key_sync_2;              // 更新认可值
            end else begin
                cnt <= cnt + 32'd1;                     // 继续计数
            end
        end else begin
            cnt <= 32'd0;                               // 输入回到旧值, 计数器清零
        end
    end

endmodule
