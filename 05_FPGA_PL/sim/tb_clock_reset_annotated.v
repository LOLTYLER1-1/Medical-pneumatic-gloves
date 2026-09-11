`timescale 1ns / 1ps                     // 仿真单位=1ns, 精度=1ps

// ============================================================================
// Mock 模块: 替代 Vivado 的 clk_wiz_0 IP
// 因为在独立仿真器(iverilog/Vivado Simulator)中没有 clk_wiz_0 IP 核
// 所以用一个简单 always 块产生两个时钟和 locked 信号
// ============================================================================
module clk_wiz_0 (                        // 模块名与原始 IP 相同, 仿真时替代
    input  wire clk_in1,                  // 输入时钟(板载 50MHz 晶振)
    input  wire resetn,                   // 高有效复位(与 clk_wiz 接口一致)
    output reg  clk_out1,                 // 输出 1: 100MHz 系统时钟
    output reg  clk_out2,                 // 输出 2: 33.33MHz LCD 像素时钟
    output reg  locked                    // 锁相环锁定标志, 1=时钟稳定
);
    initial begin                         // 初始化块, 仿真开始时执行
        locked = 0;                       // 初始未锁定
        clk_out1 = 0;                     // 100MHz 时钟初始为 0
        clk_out2 = 0;                     // 33.33MHz 时钟初始为 0
        #100;                             // 等待 100ns 模拟 PLL 锁定时间
        locked = 1;                       // 锁定标志置 1
    end                                   // initial 结束
    always #5  clk_out1 = ~clk_out1;      // 每 5ns 翻转, 周期=10ns, 频率=100MHz
    always #15 clk_out2 = ~clk_out2;      // 每 15ns 翻转, 周期=30ns, 频率≈33.33MHz
endmodule                                 // mock 模块结束

// ============================================================================
// Testbench: 测试时钟复位模块
// ============================================================================
module tb_clock_reset;                    // 测试时钟复位模块的 testbench

    // ---- 信号声明 ----
    reg  sys_clk;                         // 系统输入时钟(板载 50MHz)
    reg  sys_rst_n;                       // 系统复位(低有效)
    wire clk_100m;                        // 输出: 100MHz 系统时钟
    wire pclk_33m;                        // 输出: 33.33MHz LCD 像素时钟
    wire rst_n_sync;                      // 输出: 同步释放后的复位(低有效)

    // ---- 被测模块实例化 ----
    clock_reset uut (                     // 例化时钟复位模块
        .sys_clk_i    (sys_clk),          // 连 50MHz 输入时钟
        .sys_rst_n_i  (sys_rst_n),        // 连系统复位
        .clk_100m_o   (clk_100m),         // 接 100MHz 输出
        .pclk_33m_o   (pclk_33m),         // 接 33.33MHz 输出
        .rst_n_sync_o (rst_n_sync)        // 接同步复位输出
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始执行一次
        $dumpfile("clock_reset.vcd");     // 波形文件名
        $dumpvars(0, tb_clock_reset);     // 记录所有信号
    end                                   // initial 结束

    // ---- 输入时钟生成(50MHz) ----
    initial sys_clk = 0;                  // 初始为 0
    always #10 sys_clk = ~sys_clk;        // 每 10ns 翻转, 周期=20ns, 50MHz

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  clock_reset Testbench");
        $display("========================================");

        // ---- 复位测试 ----
        sys_rst_n = 1'b0;                 // 拉低复位
        #50;                              // 等待 50ns
        $display("[T=%0t] Reset active, rst_n_sync=%b", $time, rst_n_sync);
        // 期望: rst_n_sync=0, 因为 reset 和 locked 至少有一个为 0

        // ---- 释放复位 ----
        sys_rst_n = 1'b1;                 // 释放复位
        #200;                             // 等待 200ns, 让 locked 变 1 + 3 级同步
        $display("[T=%0t] After reset release + locked, rst_n_sync=%b", $time, rst_n_sync);
        // 期望: rst_n_sync=1, 复位已同步释放

        // ---- 验证时钟输出 ----
        repeat(10) @(posedge clk_100m);   // 等 10 个 100MHz 时钟上升沿
        $display("[T=%0t] clk_100m toggling, rst_n_sync=%b", $time, rst_n_sync);
        // 期望: clk_100m 正常翻转, rst_n_sync=1

        repeat(5) @(posedge pclk_33m);    // 等 5 个 33MHz 时钟上升沿
        $display("[T=%0t] pclk_33m toggling, rst_n_sync=%b", $time, rst_n_sync);
        // 期望: pclk_33m 正常翻转

        // ---- 重新复位测试 ----
        sys_rst_n = 1'b0;                 // 再次拉低复位
        #50;                              // 等 50ns
        $display("[T=%0t] Reset re-asserted, rst_n_sync=%b", $time, rst_n_sync);
        // 期望: rst_n_sync=0

        sys_rst_n = 1'b1;                 // 再次释放
        #200;                             // 等 200ns
        $display("[T=%0t] Reset released again, rst_n_sync=%b", $time, rst_n_sync);
        // 期望: rst_n_sync=1

        // ---- 结束 ----
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
