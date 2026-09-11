`timescale 1ns / 1ps                     // 仿真单位=1ns, 精度=1ps

module tb_buzzer_ctrl;                    // 测试蜂鸣器控制器的 testbench

    reg  clk;                             // 系统时钟
    reg  rst_n;                           // 低有效复位
    reg  trigger_i;                       // 触发信号, 高=告警(来自 safety_trigger 或急停)
    wire buzzer_o;                        // 蜂鸣器输出, 高=响

    // 为加快仿真, 时钟降到 1MHz, 蜂鸣频率提到 1kHz
    // 实际硬件: 100MHz 时钟, 2Hz 蜂鸣, 半周期=25M 周期=250ms
    // 仿真: 1MHz 时钟, 1kHz 蜂鸣, 半周期=500 周期=500us
    localparam CLK_HZ = 32'd1_000_000;    // 仿真时钟 1MHz
    localparam BEEP_FREQ_HZ = 32'd1000;   // 仿真蜂鸣 1kHz

    // ---- 被测模块实例化 ----
    buzzer_ctrl #(                        // 例化蜂鸣器控制器
        .CLK_HZ      (CLK_HZ),            // 传入仿真时钟频率
        .BEEP_FREQ_HZ(BEEP_FREQ_HZ)       // 传入仿真蜂鸣频率
    ) uut (                               // uut = Unit Under Test
        .clk_i     (clk),                 // 连时钟
        .rst_n_i   (rst_n),               // 连复位
        .trigger_i (trigger_i),           // 连触发信号
        .buzzer_o  (buzzer_o)             // 接蜂鸣器输出
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始执行一次
        $dumpfile("buzzer_ctrl.vcd");     // 波形文件名
        $dumpvars(0, tb_buzzer_ctrl);     // 记录所有信号
    end                                   // initial 结束

    // ---- 时钟生成(1MHz) ----
    initial clk = 0;                      // 时钟初始为 0
    always #500 clk = ~clk;               // 每 500ns 翻转, 周期=1000ns=1us, 频率=1MHz

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  buzzer_ctrl Testbench");
        $display("  (CLK=1MHz, BEEP=1kHz for fast sim)");
        $display("========================================");

        // ---- 复位 ----
        rst_n = 1'b0;                     // 拉低复位
        trigger_i = 1'b0;                 // 触发信号初始为 0
        #2000;                            // 等待 2us
        rst_n = 1'b1;                     // 释放复位
        #2000;                            // 再等 2us
        $display("[T=%0t] trigger=0 -> buzzer=%b (expect 0)", $time, buzzer_o);
        // 期望: buzzer=0, 触发为 0 时静音

        // ---- 触发告警 ----
        trigger_i = 1'b1;                 // 拉高触发, 开始告警
        #500000;                          // 等待 500us(半周期)
        $display("[T=%0t] trigger=1 after 0.5ms -> buzzer=%b", $time, buzzer_o);
        // 期望: buzzer 可能为 0 或 1, 取决于计数器状态

        #500000;                          // 再等 500us(共 1ms)
        $display("[T=%0t] trigger=1 after 1ms (first half period) -> buzzer=%b", $time, buzzer_o);
        // 期望: buzzer 应该翻转了(tick 已反转)

        #500000;                          // 再等 500us
        $display("[T=%0t] trigger=1 after 1.5ms -> buzzer=%b", $time, buzzer_o);

        #500000;                          // 再等 500us(共 2ms)
        $display("[T=%0t] trigger=1 after 2ms (should toggle) -> buzzer=%b", $time, buzzer_o);
        // 期望: buzzer 应该再次翻转(一个完整周期)

        // ---- 解除告警 ----
        trigger_i = 1'b0;                 // 拉低触发, 解除告警
        #1000;                            // 等 1us
        $display("[T=%0t] trigger=0 -> buzzer=%b (expect 0, counter reset)", $time, buzzer_o);
        // 期望: buzzer=0, 触发为 0 时立即静音, 计数器复位

        // ---- 结束 ----
        #2000;                            // 等 2us
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
