`timescale 1ns / 1ps                     // 仿真时间单位=1ns, 精度=1ps, 类似 Arduino delay() 的单位

module tb_safety_interlock;               // testbench 模块声明, 没有输入输出端口(顶层测试模块)

    // ---- 信号声明 ----
    // 就像 Arduino 里先定义变量, 再传给函数
    reg  [15:0] pressure_i;               // 输入: 压力值(×100), 用 reg 因为 testbench 里要赋值驱动它
    reg         pump_in_i;                // 输入: 气泵控制信号, 来自 FSM
    reg         v2_in_i;                  // 输入: 泄气阀控制信号, 来自 FSM
    wire        pump_out_o;               // 输出: 经过安全联锁后的气泵信号, wire 因为由 DUT 驱动
    wire        v2_out_o;                 // 输出: 经过安全联锁后的泄气阀信号
    wire        trigger_o;                // 输出: 超压触发标志, 给蜂鸣器和 EMIO

    // ---- 被测模块实例化 (DUT = Device Under Test) ----
    // 就像 Arduino 里创建一个类的对象, 把引脚连上
    safety_interlock #(                   // 例化 safety_interlock 模块
        .PRESSURE_LIMIT(16'd8000)         // 参数覆盖: 压力上限=8000(即 80.00kPa)
    ) uut (                               // uut = Unit Under Test, 被测单元的名字
        .pressure_i (pressure_i),         // 把 testbench 的 pressure_i 连到 DUT 的 pressure_i 端口
        .pump_in_i  (pump_in_i),          // 连气泵输入
        .v2_in_i    (v2_in_i),            // 连泄气阀输入
        .pump_out_o (pump_out_o),         // 从 DUT 接出气泵输出
        .v2_out_o   (v2_out_o),           // 从 DUT 接出泄气阀输出
        .trigger_o  (trigger_o)           // 从 DUT 接出触发标志
    );                                    // 实例化结束

    // ---- VCD 波形文件生成 ----
    // 这是仿真器的"录像机", 把信号变化录下来, 用 GTKWave 或 Vivado 查看
    initial begin                         // initial 块: 上电后只执行一次, 类似 Arduino setup()
        $dumpfile("safety_interlock.vcd"); // 指定波形文件名
        $dumpvars(0, tb_safety_interlock); // 记录本模块及其子模块的所有信号, 0 表示全层级
    end                                   // initial 块结束

    // ---- 测试激励 ----
    initial begin                         // 另一个 initial 块, 也只在仿真开始时执行一次
        $display("========================================");  // 在控制台打印分隔线
        $display("  safety_interlock Testbench");             // 打印测试名称
        $display("========================================");  // 分隔线

        // ---- 测试用例 1: 全零输入 ----
        pressure_i = 16'd0;               // 压力=0 kPa, 远低于上限
        pump_in_i = 1'b0;                 // 气泵关闭
        v2_in_i = 1'b0;                   // 泄气阀开(失电=开, fail-safe)
        #10;                              // 等待 10ns, 让组合逻辑输出稳定(组合逻辑瞬间出结果, 但给点裕量)
        $display("[T=%0t] pressure=0, pump_in=0, v2_in=0 -> trigger=%b pump_out=%b v2_out=%b",
                 $time, trigger_o, pump_out_o, v2_out_o);
        // $time 返回当前仿真时间, %0t 表示不带前导零的时间格式
        // 期望: trigger=0(未超压), pump_out=0(透传), v2_out=0(透传)

        // ---- 测试用例 2: 正常压力, 气泵和泄气阀都开 ----
        pressure_i = 16'd5000;            // 压力=50.00 kPa, 正常范围内
        pump_in_i = 1'b1;                 // 气泵开
        v2_in_i = 1'b1;                   // 泄气阀关(通电=关)
        #10;                              // 等待输出稳定
        $display("[T=%0t] pressure=5000, pump_in=1, v2_in=1 -> trigger=%b pump_out=%b v2_out=%b",
                 $time, trigger_o, pump_out_o, v2_out_o);
        // 期望: trigger=0(50<80), pump_out=1(透传), v2_out=1(透传)

        // ---- 测试用例 3: 刚好达到上限 ----
        pressure_i = 16'd8000;            // 压力=80.00 kPa, 刚好达到硬上限
        pump_in_i = 1'b1;                 // 气泵开
        v2_in_i = 1'b1;                   // 泄气阀关
        #10;                              // 等待
        $display("[T=%0t] pressure=8000, pump_in=1, v2_in=1 -> trigger=%b pump_out=%b v2_out=%b",
                 $time, trigger_o, pump_out_o, v2_out_o);
        // 期望: trigger=1(>=8000), pump_out=0(强制停), v2_out=0(强制泄)

        // ---- 测试用例 4: 超过上限 ----
        pressure_i = 16'd9000;            // 压力=90.00 kPa, 超过上限
        pump_in_i = 1'b1;                 // 气泵开
        v2_in_i = 1'b1;                   // 泄气阀关
        #10;                              // 等待
        $display("[T=%0t] pressure=9000, pump_in=1, v2_in=1 -> trigger=%b pump_out=%b v2_out=%b",
                 $time, trigger_o, pump_out_o, v2_out_o);
        // 期望: trigger=1, pump_out=0, v2_out=0(同上, 超压强制切断)

        // ---- 测试用例 5: 超压但输入已关 ----
        pressure_i = 16'd9000;            // 压力=90.00 kPa, 仍超压
        pump_in_i = 1'b0;                 // 气泵已关
        v2_in_i = 1'b0;                   // 泄气阀已开
        #10;                              // 等待
        $display("[T=%0t] pressure=9000, pump_in=0, v2_in=0 -> trigger=%b pump_out=%b v2_out=%b",
                 $time, trigger_o, pump_out_o, v2_out_o);
        // 期望: trigger=1(仍超压), pump_out=0(透传0), v2_out=0(透传0)
        // 注意: 即使输入已关, trigger 仍为 1, 因为压力还超上限, 蜂鸣器会持续响

        // ---- 测试用例 6: 压力回落到安全范围 ----
        pressure_i = 16'd7000;            // 压力=70.00 kPa, 低于上限
        pump_in_i = 1'b0;                 // 气泵关
        v2_in_i = 1'b0;                   // 泄气阀开
        #10;                              // 等待
        $display("[T=%0t] pressure=7000, pump_in=0, v2_in=0 -> trigger=%b pump_out=%b v2_out=%b",
                 $time, trigger_o, pump_out_o, v2_out_o);
        // 期望: trigger=0(安全), pump_out=0(透传), v2_out=0(透传)

        // ---- 测试结束 ----
        $display("========================================");
        $display("  All tests passed!");   // 打印通过信息(这里不自动检查, 需人工看输出)
        $display("========================================");
        $finish;                          // 结束仿真, 类似 Arduino 程序结束
    end                                   // initial 块结束

endmodule                                 // 模块结束
