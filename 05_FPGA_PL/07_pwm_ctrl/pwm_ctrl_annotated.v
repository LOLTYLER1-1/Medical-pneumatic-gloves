//=============================================================================
// File        : pwm_ctrl_annotated.v   ★教学版★
// 类比: Arduino 的 analogWrite() 内部就是这个逻辑
//       但 Arduino 一开就是全速, 这里多了"软启动斜坡"避免气泵突然启动冲击
//
// 原理:
//   PWM = 在固定周期内, 一段时间为高一段时间为低
//   占空比 = 高电平时间 / 总周期
//   软启动 = 上电时 duty 从 0 → 目标值缓慢增加, 像汽车踩油门
//=============================================================================

`timescale 1ns / 1ps

module pwm_ctrl #(
    parameter WIDTH             = 8,                    // 占空比位宽(8 = 256 级)
    parameter RAMP_CYC_PER_STEP = 32'd195_312           // 每加 1 级 duty 所需时钟数 (≈ 2ms)
)(                                                      // 256 级 * 2ms = 500ms 完成软启动
    input  wire             clk_i,                      // 100 MHz
    input  wire             rst_n_i,                    // 同步复位
    input  wire [WIDTH-1:0] duty_i,                     // 目标占空比 0~255
    input  wire             enable_i,                   // 1=PWM 输出, 0=立即关
    output reg              pwm_o                       // PWM 输出
);

    reg [WIDTH-1:0] cnt;                                // PWM 载波计数器
    reg [WIDTH-1:0] duty_eff;                           // 实际有效占空比(逐渐爬升)
    reg [31:0]      ramp_cnt;                           // 斜坡时间计数器

    // === 软启动斜坡: duty_eff 从 0 慢慢爬升到 duty_i ===
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            duty_eff <= {WIDTH{1'b0}};                  // 复位: 0
            ramp_cnt <= 32'd0;
        end else if (!enable_i) begin
            duty_eff <= {WIDTH{1'b0}};                  // 失能: 立即归零
            ramp_cnt <= 32'd0;
        end else if (duty_eff < duty_i) begin           // 还没爬到目标
            if (ramp_cnt >= RAMP_CYC_PER_STEP - 1) begin// 等够一个步进时间
                ramp_cnt <= 32'd0;
                duty_eff <= duty_eff + 1'b1;            // duty 加 1
            end else begin
                ramp_cnt <= ramp_cnt + 32'd1;
            end
        end else begin
            duty_eff <= duty_i;                         // 已达目标, 保持
            ramp_cnt <= 32'd0;
        end
    end

    // === PWM 生成: cnt 自由循环, 与 duty_eff 比大小决定输出 ===
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt   <= {WIDTH{1'b0}};
            pwm_o <= 1'b0;
        end else if (!enable_i) begin
            cnt   <= {WIDTH{1'b0}};
            pwm_o <= 1'b0;
        end else begin
            cnt   <= cnt + 1'b1;                        // 0~255 循环
            pwm_o <= (cnt < duty_eff) ? 1'b1 : 1'b0;    // cnt 较小时输出高
        end
    end

endmodule
