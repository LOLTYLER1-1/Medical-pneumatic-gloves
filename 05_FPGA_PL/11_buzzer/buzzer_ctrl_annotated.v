//=============================================================================
// File        : buzzer_ctrl_annotated.v   (教学版, 不加入工程综合)
// Module      : buzzer_ctrl
// Description : 板载蜂鸣器告警驱动 - 每行注释版
//
// Arduino 类比:
//   有源蜂鸣器 = digitalWrite(BUZZ, HIGH) 就响, LOW 就停; 不需要 tone()/PWM
//   Arduino 写法:
//     if (alarm) { digitalWrite(BUZZ, HIGH); delay(250);
//                  digitalWrite(BUZZ, LOW);  delay(250); }
//   Verilog 等价做法:
//     用 100MHz 时钟做计数器, 数到 25_000_000 就翻转 tick (实现 2Hz 方波)
//     buzzer_o = trigger & tick
//=============================================================================

`timescale 1ns / 1ps                                    // 时间单位 1ns, 精度 1ps

module buzzer_ctrl #(
    parameter CLK_HZ       = 32'd100_000_000,           // 输入时钟频率 = 100 MHz
    parameter BEEP_FREQ_HZ = 32'd2                      // 蜂鸣频率 2 Hz (每秒 2 个滴声)
)(
    input  wire clk_i,                                  // 100MHz 时钟
    input  wire rst_n_i,                                // 异步低有效复位
    input  wire trigger_i,                              // 告警触发 (高有效)
    output wire buzzer_o                                // 接 M14 板载蜂鸣器
);

    //--------------------------------------------------------------------------
    // 半周期常量: 100_000_000 / 2 / 2 = 25_000_000 个 100MHz 周期 = 250 ms
    //--------------------------------------------------------------------------
    localparam HALF_PERIOD = CLK_HZ / BEEP_FREQ_HZ / 2; // = 25_000_000

    reg [25:0] counter;                                 // 26 位 ($clog2(25M) = 25)
    reg        tick;                                    // 2Hz 方波内部信号

    //--------------------------------------------------------------------------
    // 分频计数器:
    //   trigger=0 时强制清零 (复位状态), 防止再次告警时从中间相位开始响
    //   trigger=1 时计到 HALF_PERIOD-1 翻转一次 tick
    //--------------------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin                             // 上电/手动复位
            counter <= 26'd0;
            tick    <= 1'b0;
        end else if (!trigger_i) begin                  // 无告警: 静止状态
            counter <= 26'd0;
            tick    <= 1'b0;
        end else if (counter >= HALF_PERIOD - 1) begin  // 250ms 到, 翻转
            counter <= 26'd0;
            tick    <= ~tick;
        end else begin                                  // 继续计数
            counter <= counter + 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // 输出:
    //   trigger=0 → 强制 0 (静音, 即使 tick 还没清零也屏蔽)
    //   trigger=1 → 输出 2Hz 方波 (250ms 高, 250ms 低 → 滴—滴—滴—)
    // 高电平驱动 NPN 三极管 → 蜂鸣器响
    //--------------------------------------------------------------------------
    assign buzzer_o = trigger_i & tick;

endmodule
