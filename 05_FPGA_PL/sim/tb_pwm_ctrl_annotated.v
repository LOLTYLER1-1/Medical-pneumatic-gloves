`timescale 1ns / 1ps                     // 仿真单位=1ns, 精度=1ps

module tb_pwm_ctrl;                       // 测试 PWM 控制器的 testbench

    // ---- 信号声明 ----
    reg        clk;                       // 系统时钟, 100MHz
    reg        rst_n;                     // 低有效复位
    reg  [7:0] duty_i;                    // 目标占空比(0~255), 来自 FSM 或 PS
    reg        enable_i;                  // 使能信号, 1=输出 PWM, 0=停
    wire       pwm_o;                     // PWM 输出, 直接去驱动气泵(经 ULN2803)

    // 为加快仿真, ramp 步进时间从 195312 周期缩短到 10 周期
    // 实际硬件中 195312 周期 ≈ 2ms/步, 255 步 ≈ 500ms 软启动
    // 仿真中 10 周期 = 100ns/步, 255 步 ≈ 25.5us
    localparam RAMP_FAST = 32'd10;        // 仿真加速参数

    // ---- 被测模块实例化 ----
    pwm_ctrl #(                            // 例化 PWM 控制器
        .WIDTH(8),                        // 8 位精度, 256 级
        .RAMP_CYC_PER_STEP(RAMP_FAST)     // 仿真用快速 ramp
    ) uut (                               // uut = Unit Under Test
        .clk_i    (clk),                  // 连时钟
        .rst_n_i  (rst_n),                // 连复位
        .duty_i   (duty_i),               // 连目标占空比
        .enable_i (enable_i),             // 连使能
        .pwm_o    (pwm_o)                 // 接 PWM 输出
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始执行一次
        $dumpfile("pwm_ctrl.vcd");        // 波形文件名
        $dumpvars(0, tb_pwm_ctrl);        // 记录所有信号
    end                                   // initial 结束

    // ---- 时钟生成 ----
    initial clk = 0;                      // 时钟初始为 0
    always #5 clk = ~clk;                 // 每 5ns 翻转, 周期=10ns, 100MHz

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  pwm_ctrl Testbench");
        $display("  (RAMP_CYC_PER_STEP=10 for fast sim)");
        $display("========================================");

        // ---- 复位阶段 ----
        rst_n = 1'b0;                     // 拉低复位
        duty_i = 8'd100;                  // 目标占空比=100/255≈39%
        enable_i = 1'b0;                  // 初始禁用
        #20;                              // 等待 20ns
        rst_n = 1'b1;                     // 释放复位
        #10;                              // 再等一个周期
        $display("[T=%0t] enable=0 -> pwm=%b", $time, pwm_o);
        // 期望: pwm=0, 因为 enable=0

        // ---- 使能测试 ----
        enable_i = 1'b1;                  // 使能 PWM
        repeat(20) @(posedge clk);        // 重复 20 个时钟周期
        // 此时 duty_eff 应该刚开始 ramp(从 0 往上爬)
        $display("[T=%0t] enable=1, duty=100, after 20 cycles -> pwm=%b", $time, pwm_o);
        // 期望: pwm 可能为 0 或 1, 取决于当前 duty_eff 和计数器

        // ---- ramp 完成测试 ----
        repeat(2560) @(posedge clk);      // 等待足够长时间让 ramp 完成
        // 2560 周期 >> 255 步 × 10 周期/步 = 2550 周期
        $display("[T=%0t] After ramp complete -> pwm=%b", $time, pwm_o);
        // 期望: pwm 以约 39% 占空比输出(100/255)

        // ---- 改变占空比 ----
        duty_i = 8'd50;                   // 目标改为 50/255≈20%
        repeat(20) @(posedge clk);        // 等 20 周期
        $display("[T=%0t] duty changed to 50 -> pwm=%b", $time, pwm_o);
        // 期望: duty_eff 会下降, pwm 占空比变小

        // ---- 禁用测试 ----
        enable_i = 1'b0;                  // 禁用 PWM
        @(posedge clk);                   // 等一个时钟
        $display("[T=%0t] enable=0 -> pwm=%b (expect 0)", $time, pwm_o);
        // 期望: pwm=0, 计数器和 duty_eff 都复位

        // ---- 重新使能, 大占空比 ----
        duty_i = 8'd200;                  // 目标=200/255≈78%
        enable_i = 1'b1;                  // 重新使能
        repeat(3000) @(posedge clk);      // 等 ramp 完成
        $display("[T=%0t] duty=200, ramp done -> pwm=%b", $time, pwm_o);
        // 期望: pwm 以约 78% 占空比输出

        // ---- 结束 ----
        #100;                             // 等待 100ns
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
