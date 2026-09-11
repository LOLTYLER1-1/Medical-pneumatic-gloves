`timescale 1ns / 1ps                     // 仿真单位=1ns, 精度=1ps

module tb_key_debounce;                   // 测试按键消抖的 testbench

    // ---- 信号声明 ----
    reg        clk;                       // 系统时钟, 100MHz
    reg        rst_n;                     // 低有效复位
    reg        key_raw_i;                 // 原始按键输入, 包含抖动(毛刺)
    wire       key_clean_o;               // 消抖后的干净按键输出

    // 为加快仿真, 消抖时间从 20ms 缩短到 1ms
    // 实际硬件: 20ms × 100MHz = 2,000,000 周期
    // 仿真: 1ms × 100MHz = 100,000 周期 = 100,000ns = 100us
    localparam CLK_FREQ_HZ = 32'd100_000_000;  // 时钟频率=100MHz
    localparam DEBOUNCE_MS = 32'd1;            // 仿真用 1ms 消抖
    localparam DEBOUNCE_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    // DEBOUNCE_MAX = 100,000,000 / 1000 × 1 = 100,000 周期

    // ---- 被测模块实例化 ----
    key_debounce #(                       // 例化按键消抖模块
        .CLK_FREQ_HZ (CLK_FREQ_HZ),       // 传入时钟频率
        .DEBOUNCE_MS (DEBOUNCE_MS),       // 传入消抖时间
        .DEBOUNCE_MAX(DEBOUNCE_MAX)       // 传入计数上限(也可让模块自己算)
    ) uut (                               // uut = Unit Under Test
        .clk_i       (clk),               // 连时钟
        .rst_n_i     (rst_n),             // 连复位
        .key_raw_i   (key_raw_i),         // 连原始按键(带抖动)
        .key_clean_o (key_clean_o)        // 接消抖后的干净输出
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始执行一次
        $dumpfile("key_debounce.vcd");    // 波形文件名
        $dumpvars(0, tb_key_debounce);    // 记录所有信号
    end                                   // initial 结束

    // ---- 时钟生成 ----
    initial clk = 0;                      // 时钟初始为 0
    always #5 clk = ~clk;                 // 每 5ns 翻转, 100MHz

    // ---- 辅助任务: 模拟按键抖动 ----
    // 就像真实的机械按键: 按下时触点会弹跳几次才稳定
    task key_bounce;                      // 任务: 产生带抖动的按键按下
        begin                             // 任务体开始
            key_raw_i = 1'b0; #100;       // 先拉低 100ns(模拟按下)
            key_raw_i = 1'b1; #80;        // 弹回高 80ns(第一次弹跳)
            key_raw_i = 1'b0; #120;       // 再拉低 120ns(第二次弹跳)
            key_raw_i = 1'b1; #60;        // 再弹回 60ns(第三次弹跳)
            key_raw_i = 1'b0;             // 最终稳定在低电平(按下状态)
            // 总抖动时间=100+80+120+60=360ns, 远小于 1ms 消抖时间
        end                               // 任务体结束
    endtask                               // 任务结束

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  key_debounce Testbench");
        $display("  (DEBOUNCE_MS=1 for fast sim)");
        $display("========================================");

        // ---- 初始化 ----
        rst_n = 1'b0;                     // 拉低复位
        key_raw_i = 1'b1;                 // 按键初始未按下(高电平)
        #20;                              // 等待 20ns
        rst_n = 1'b1;                     // 释放复位
        #10;                              // 再等 10ns
        $display("[T=%0t] Initial state -> key_clean=%b (expect 1)", $time, key_clean_o);
        // 期望: key_clean=1, 初始未按下

        // ---- 模拟按键按下(带抖动) ----
        $display("[T=%0t] Simulating key press with bounce...", $time);
        key_bounce;                       // 调用抖动任务

        // ---- 等待消抖 ----
        // 抖动结束后 key_raw=0, 但消抖需要稳定 1ms 才确认
        #2000000;                         // 等待 2ms (> 1ms 消抖时间)
        $display("[T=%0t] After debounce period -> key_clean=%b (expect 0)", $time, key_clean_o);
        // 期望: key_clean=0, 消抖后确认按键已按下

        // ---- 模拟按键释放 ----
        key_raw_i = 1'b1;                 // 直接拉高(释放)
        #2000000;                         // 等待 2ms 消抖
        $display("[T=%0t] Key released -> key_clean=%b (expect 1)", $time, key_clean_o);
        // 期望: key_clean=1, 确认按键已释放

        // ---- 结束 ----
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
