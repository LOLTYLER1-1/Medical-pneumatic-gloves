`timescale 1ns / 1ps                     // 仿真单位=1ns, 精度=1ps

module tb_glove_fsm;                      // 测试手套主状态机的 testbench

    // ---- 信号声明 ----
    reg         clk;                      // 系统时钟, 100MHz
    reg         rst_n;                    // 低有效复位
    reg         grip_req_i;               // 抓握请求(来自 PS 或触摸检测), 类似 Arduino 按钮按下
    reg         release_req_i;            // 释放请求(来自 PS 或触摸检测)
    reg         emerg_i;                  // 急停信号, 高有效(来自消抖后的急停按键)
    reg  [15:0] pressure_i;               // 当前气压值(kPa×100), 来自气压传感器
    reg  [15:0] setpoint_i;               // 目标气压(kPa×100), 来自 PS 设定
    wire [2:0]  state_o;                  // 当前状态输出, 送 lcd_display 显示颜色
    wire        pump_o;                   // 气泵控制输出, 1=转, 0=停
    wire        v2_o;                     // 泄气阀控制输出, 1=关(密闭), 0=开(泄气)

    // ---- 被测模块实例化 ----
    glove_fsm #(                          // 例化主状态机
        .PRESSURE_MIN(16'd100)            // 参数: 低于 1.00kPa 视为已完全泄气
    ) uut (                               // uut = Unit Under Test
        .clk_i         (clk),             // 连 100MHz 时钟
        .rst_n_i       (rst_n),           // 连复位
        .grip_req_i    (grip_req_i),      // 连抓握请求
        .release_req_i (release_req_i),   // 连释放请求
        .emerg_i       (emerg_i),         // 连急停
        .pressure_i    (pressure_i),      // 连当前气压
        .setpoint_i    (setpoint_i),      // 连目标气压
        .state_o       (state_o),         // 接状态输出
        .pump_o        (pump_o),          // 接气泵控制
        .v2_o          (v2_o)             // 接泄气阀控制
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始只执行一次
        $dumpfile("glove_fsm.vcd");       // 波形文件名
        $dumpvars(0, tb_glove_fsm);       // 记录所有信号
    end                                   // initial 结束

    // ---- 时钟生成 ----
    initial clk = 0;                      // 时钟初始为 0
    always #5 clk = ~clk;                 // 每 5ns 翻转, 100MHz

    // ---- 辅助任务: 打印当前状态 ----
    // 就像 Arduino 里写一个函数来串口打印状态
    task print_state;                     // task: Verilog 里的"函数", 可含时序控制
        begin                             // task 体开始
            case (state_o)                // 根据状态值打印对应名称
                3'd0: $display("[T=%0t] state=IDLE      pump=%b v2=%b", $time, pump_o, v2_o);
                // IDLE: 空闲, 气泵停, 泄气阀开(失电), 与大气相通
                3'd1: $display("[T=%0t] state=GRIP      pump=%b v2=%b", $time, pump_o, v2_o);
                // GRIP: 抓握中, 气泵转, 泄气阀关(密闭充气)
                3'd2: $display("[T=%0t] state=HOLD      pump=%b v2=%b", $time, pump_o, v2_o);
                // HOLD: 保持, 气泵停, 泄气阀关(保持气压)
                3'd3: $display("[T=%0t] state=RELEASE   pump=%b v2=%b", $time, pump_o, v2_o);
                // RELEASE: 释放, 气泵停, 泄气阀开(泄气)
                3'd4: $display("[T=%0t] state=EMERGENCY pump=%b v2=%b", $time, pump_o, v2_o);
                // EMERGENCY: 急停, 全部失电, 泄气阀开(fail-safe)
                default: $display("[T=%0t] state=UNKNOWN   pump=%b v2=%b", $time, pump_o, v2_o);
                // 不可能到达的默认分支, 防 latch
            endcase                       // case 结束
        end                               // task 体结束
    endtask                               // task 结束

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  glove_fsm Testbench");              // 打印标题
        $display("========================================");

        // ---- 初始化 ----
        rst_n = 1'b0;                     // 拉低复位
        grip_req_i = 1'b0;                // 请求信号初始为 0
        release_req_i = 1'b0;             // 释放请求初始为 0
        emerg_i = 1'b0;                   // 急停未按下
        pressure_i = 16'd0;               // 初始气压为 0
        setpoint_i = 16'd3000;            // 目标气压=30.00kPa
        #20;                              // 等待 20ns, 覆盖 2 个时钟沿
        rst_n = 1'b1;                     // 释放复位
        @(posedge clk); #1;               // 等一个上升沿+1ns偏移, 在时钟后采样(避开竞争)
        print_state;                      // 打印初始状态
        // 期望: IDLE, pump=0, v2=0(泄气阀开)

        // ---- 测试 1: 按抓握按钮 ----
        grip_req_i = 1'b1;                // 模拟按下"抓握"按钮
        @(posedge clk); #1;               // 等时钟, 状态机是时序逻辑, 下一拍才变
        print_state;                      // 打印状态
        // 期望: 从 IDLE 进入 GRIP
        grip_req_i = 1'b0;                // 松开按钮(请求是脉冲还是电平? 当前是电平有效)

        // ---- 测试 2: 气压上升中(还没到目标) ----
        pressure_i = 16'd2000;            // 气压=20.00kPa, 还没到 30kPa
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 仍在 GRIP(气压<目标)

        // ---- 测试 3: 气压达到目标 ----
        pressure_i = 16'd3000;            // 气压=30.00kPa, 刚好达到目标
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 从 GRIP 进入 HOLD(气压>=setpoint)

        // ---- 测试 4: 气压超过目标(还在 HOLD) ----
        pressure_i = 16'd3500;            // 气压=35.00kPa
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 仍在 HOLD

        // ---- 测试 5: 按释放按钮 ----
        release_req_i = 1'b1;             // 按下"释放"按钮
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 从 HOLD 进入 RELEASE
        release_req_i = 1'b0;             // 松开按钮

        // ---- 测试 6: 气压泄到接近 0 ----
        pressure_i = 16'd50;              // 气压=0.50kPa, 低于 PRESSURE_MIN(100)
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 从 RELEASE 回到 IDLE(气压<=100)

        // ---- 测试 7: 急停 ----
        emerg_i = 1'b1;                   // 按下急停(高有效)
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 无条件进入 EMERGENCY
        emerg_i = 1'b0;                   // 松开急停

        // ---- 测试 8: 急停释放后气压已泄完 ----
        pressure_i = 16'd0;               // 气压已泄完
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 从 EMERGENCY 回到 IDLE(气压<=100)

        // ---- 测试 9: 重新抓握 ----
        grip_req_i = 1'b1;                // 再按抓握
        @(posedge clk); #1;               // 等时钟
        print_state;                      // 打印
        // 期望: 回到 GRIP
        grip_req_i = 1'b0;                // 松开

        // ---- 结束 ----
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
