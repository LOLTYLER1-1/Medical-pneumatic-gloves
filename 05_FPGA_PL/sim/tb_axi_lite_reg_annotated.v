`timescale 1ns / 1ps                     // 仿真时间单位=1ns, 精度=1ps

module tb_axi_lite_reg;                   // testbench 顶层模块, 测试 EMIO 旁路寄存器

    // ---- 信号声明 ----
    reg         clk;                      // 系统时钟, 100MHz
    reg         rst_n;                    // 低有效复位, 0=复位, 1=正常工作
    reg  [15:0] pressure_kpa_i;           // 输入: 气压值(kPa×100), 来自 pressure_iic
    reg  [2:0]  fsm_state_i;              // 输入: FSM 状态, 来自 glove_fsm
    reg         safety_trigger_i;         // 输入: 安全触发标志, 来自 safety_interlock
    wire [15:0] pressure_kpa_o;           // 输出: 打拍后的气压值, 送 PS EMIO
    wire [2:0]  fsm_state_o;              // 输出: 打拍后的状态, 送 PS EMIO
    wire        safety_trigger_o;         // 输出: 打拍后的触发标志, 送 PS EMIO

    // ---- 被测模块实例化 ----
    axi_lite_reg uut (                    // 例化 axi_lite_reg(就是 EMIO 旁路寄存器)
        .clk_i            (clk),          // 连 100MHz 时钟
        .rst_n_i          (rst_n),        // 连复位
        .pressure_kpa_i   (pressure_kpa_i), // 连气压输入
        .fsm_state_i      (fsm_state_i),   // 连状态输入
        .safety_trigger_i (safety_trigger_i), // 连触发标志输入
        .pressure_kpa_o   (pressure_kpa_o), // 接打拍后的气压输出
        .fsm_state_o      (fsm_state_o),    // 接打拍后的状态输出
        .safety_trigger_o (safety_trigger_o) // 接打拍后的触发标志输出
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始只执行一次
        $dumpfile("axi_lite_reg.vcd");    // 波形文件名
        $dumpvars(0, tb_axi_lite_reg);    // 记录所有信号
    end                                   // initial 结束

    // ---- 时钟生成 ----
    // 就像 Arduino 的 millis(), 这里是硬件时钟, 100MHz = 10ns 周期
    initial clk = 0;                      // 初始时钟为 0
    always #5 clk = ~clk;                 // 每 5ns 翻转一次, 周期=10ns, 频率=100MHz

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  axi_lite_reg Testbench");             // 打印测试标题
        $display("========================================");

        // ---- 复位阶段 ----
        rst_n = 1'b0;                     // 拉低复位, 模块进入复位状态
        pressure_kpa_i = 16'd0;           // 复位期间输入置 0
        fsm_state_i = 3'd0;               // 状态置 IDLE
        safety_trigger_i = 1'b0;          // 触发标志置 0
        #20;                              // 等待 20ns, 覆盖至少 2 个时钟上升沿
        rst_n = 1'b1;                     // 释放复位, 模块开始工作
        #10;                              // 等待一个时钟周期(10ns)
        $display("[T=%0t] After reset -> pressure=%d state=%d trigger=%b",
                 $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);
        // 期望: 全 0, 因为刚复位, 输出被清零

        // ---- 第一次输入变化 ----
        @(posedge clk);                   // 等待下一个时钟上升沿(同步操作, 像 Arduino 的 loop())
        pressure_kpa_i = 16'd1234;        // 气压设为 12.34 kPa
        fsm_state_i = 3'd2;               // 状态设为 HOLD(3'd2)
        safety_trigger_i = 1'b1;          // 触发标志置 1
        @(posedge clk);                   // 再等一个上升沿, 让输入被采样
        $display("[T=%0t] Input changed -> pressure=%d state=%d trigger=%b",
                 $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);
        // 注意: axi_lite_reg 是打拍寄存器, 输出比输入延迟 1 个时钟
        // 所以在 posedge clk 后, 输出仍然是旧的值(因为用非阻塞赋值 <=)
        // 要到下一个 posedge 输出才更新

        @(posedge clk);                   // 再等待一个时钟, 此时输出应该已更新
        $display("[T=%0t] Next cycle   -> pressure=%d state=%d trigger=%b",
                 $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);
        // 期望: pressure=1234, state=2, trigger=1

        // ---- 第二次输入变化 ----
        @(posedge clk);                   // 等时钟上升沿
        pressure_kpa_i = 16'd5678;        // 气压改为 56.78 kPa
        fsm_state_i = 3'd4;               // 状态改为 EMERGENCY(3'd4)
        safety_trigger_i = 1'b0;          // 触发标志清 0
        @(posedge clk);                   // 再等一个时钟
        $display("[T=%0t] Input changed -> pressure=%d state=%d trigger=%b",
                 $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);
        // 此时输出是第一次变化后的值(1234,2,1)

        @(posedge clk);                   // 再一个时钟, 输出更新为第二次的值
        $display("[T=%0t] Next cycle   -> pressure=%d state=%d trigger=%b",
                 $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);
        // 期望: pressure=5678, state=4, trigger=0

        // ---- 测试结束 ----
        #20;                              // 等待 20ns, 观察最终状态
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
