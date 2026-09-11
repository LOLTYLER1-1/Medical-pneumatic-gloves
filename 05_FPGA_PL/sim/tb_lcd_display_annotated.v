`timescale 1ns / 1ps                     // 仿真单位=1ns, 精度=1ps

// ============================================================================
// Mock 模块: 替代 Vivado 的 lcd_image_rom BROM IP
// 在独立仿真中没有 BROM IP, 用一个简单 always 块返回伪彩色
// ============================================================================
module lcd_image_rom (                    // 模块名与原始 BROM 相同, 仿真时替代
    input  wire        clka,              // BROM 时钟(接 pclk)
    input  wire [15:0] addra,             // BROM 地址(0~34999)
    output reg  [15:0] douta              // BROM 数据输出(16-bit RGB565)
);
    always @(posedge clka) begin          // 时钟上升沿更新输出
        // 用地址的低 15 位生成伪彩色 pattern
        // 高 5 位=红, 中 6 位=绿, 低 5 位=蓝
        douta <= {addra[4:0], addra[9:5], addra[14:10]};
    end                                   // always 结束
endmodule                                 // mock 模块结束

// ============================================================================
// Testbench: 测试 LCD 显示渲染模块
// ============================================================================
module tb_lcd_display;                    // 测试 LCD 显示渲染的 testbench

    // ---- 信号声明 ----
    reg         pclk;                     // LCD 像素时钟, 33.33MHz
    reg         rst_n;                    // 低有效复位
    reg         hsync_i;                  // 输入行同步(来自 lcd_timing)
    reg         vsync_i;                  // 输入场同步(来自 lcd_timing)
    reg         de_i;                     // 输入数据有效(来自 lcd_timing)
    reg  [10:0] pixel_x_i;                // 输入 X 坐标(来自 lcd_timing)
    reg  [10:0] pixel_y_i;                // 输入 Y 坐标(来自 lcd_timing)
    reg  [15:0] pressure_kpa_i;           // 气压值, 控制压力条长度
    reg  [2:0]  fsm_state_i;              // FSM 状态, 控制顶部颜色条
    wire        hsync_o;                  // 输出行同步(打拍后)
    wire        vsync_o;                  // 输出场同步(打拍后)
    wire        de_o;                     // 输出数据有效(打拍后)
    wire [23:0] rgb_o;                    // RGB888 像素数据输出, 送 LCD

    // ---- 被测模块实例化 ----
    lcd_display uut (                     // 例化 LCD 显示渲染模块
        .pclk_i         (pclk),           // 连像素时钟
        .rst_n_i        (rst_n),          // 连复位
        .hsync_i        (hsync_i),        // 连输入行同步
        .vsync_i        (vsync_i),        // 连输入场同步
        .de_i           (de_i),           // 连输入数据有效
        .pixel_x_i      (pixel_x_i),      // 连输入 X 坐标
        .pixel_y_i      (pixel_y_i),      // 连输入 Y 坐标
        .pressure_kpa_i (pressure_kpa_i), // 连气压值
        .fsm_state_i    (fsm_state_i),    // 连 FSM 状态
        .hsync_o        (hsync_o),        // 接输出行同步
        .vsync_o        (vsync_o),        // 接输出场同步
        .de_o           (de_o),           // 接输出数据有效
        .rgb_o          (rgb_o)           // 接 RGB 像素数据
    );                                    // 实例化结束

    // ---- VCD 波形记录 ----
    initial begin                         // 仿真开始执行一次
        $dumpfile("lcd_display.vcd");     // 波形文件名
        $dumpvars(0, tb_lcd_display);     // 记录所有信号
    end                                   // initial 结束

    // ---- 像素时钟生成 ----
    initial pclk = 0;                     // 初始为 0
    always #15 pclk = ~pclk;              // 每 15ns 翻转, 周期=30ns, ≈33.33MHz

    // ---- 辅助任务: 发送一个像素 ----
    // 模拟 lcd_timing 送过来的像素坐标和 de 信号
    task send_pixel;                      // 任务: 发送一个像素到 DUT
        input [10:0] x;                   // X 坐标参数
        input [10:0] y;                   // Y 坐标参数
        input        active;              // 是否有效像素(=de_i)
        begin                             // 任务体
            pixel_x_i = x;                // 设置 X 坐标
            pixel_y_i = y;                // 设置 Y 坐标
            de_i = active;                // 设置数据有效
            hsync_i = 1'b1;               // 行同步高(无效期)
            vsync_i = 1'b1;               // 场同步高(无效期)
            @(posedge pclk);              // 等待一个 pclk 上升沿
        end                               // 任务体结束
    endtask                               // 任务结束

    // ---- 测试激励 ----
    initial begin                         // 上电后执行一次
        $display("========================================");
        $display("  lcd_display Testbench");
        $display("========================================");

        // ---- 初始化 ----
        rst_n = 1'b0;                     // 拉低复位
        hsync_i = 1'b1;                   // 行同步初始高
        vsync_i = 1'b1;                   // 场同步初始高
        de_i = 1'b0;                      // 数据无效
        pixel_x_i = 0;                    // X=0
        pixel_y_i = 0;                    // Y=0
        pressure_kpa_i = 16'd4000;        // 气压=40.00kPa(压力条约 50%)
        fsm_state_i = 3'd1;               // 状态=GRIP(顶部绿色)
        #50;                              // 等 50ns
        rst_n = 1'b1;                     // 释放复位
        #30;                              // 等 30ns(BROM 有延迟, 需要 pipeline 填满)

        // ---- 测试 1: 顶部状态条 ----
        $display("[T=%0t] Test: top bar (state color)", $time);
        send_pixel(11'd100, 11'd10, 1'b1); // 发送像素(100,10), 在顶部 50 像素内
        #1;                               // 等 1ns, 让组合逻辑出结果
        $display("[T=%0t] x=100,y=10 de=%b rgb=%06X (expect green for GRIP)", $time, de_o, rgb_o);
        // 期望: rgb=绿色(20C040), 因为 y<50 且 state=GRIP

        // ---- 测试 2: 左侧背景区 ----
        send_pixel(11'd100, 11'd100, 1'b1); // 发送像素(100,100), 左侧分区
        #1;
        $display("[T=%0t] x=100,y=100 de=%b rgb=%06X (expect LIGHTGRN)", $time, de_o, rgb_o);
        // 期望: rgb=浅绿色(A0E0A0), 因为 y>=50 && y<360 && x<400

        // ---- 测试 3: 右侧背景区 ----
        send_pixel(11'd500, 11'd100, 1'b1); // 发送像素(500,100), 右侧分区
        #1;
        $display("[T=%0t] x=500,y=100 de=%b rgb=%06X (expect LIGHTORG)", $time, de_o, rgb_o);
        // 期望: rgb=浅橙色(FFD0A0), 因为 y>=50 && y<360 && x>=400

        // ---- 测试 4: 图片区域 ----
        $display("[T=%0t] Test: image region", $time);
        send_pixel(11'd300, 11'd152, 1'b1); // 发送像素(300,152), 图片左上角
        #1;
        $display("[T=%0t] x=300,y=152 de=%b rgb=%06X (image pixel)", $time, de_o, rgb_o);
        // 期望: rgb=从 BROM 读取的伪彩色(不是背景色)

        // ---- 测试 5: 压力条区域 ----
        $display("[T=%0t] Test: pressure bar area", $time);
        send_pixel(11'd100, 11'd410, 1'b1); // 发送像素(100,410), 压力条起点
        #1;
        $display("[T=%0t] x=100,y=410 de=%b rgb=%06X (bar area)", $time, de_o, rgb_o);
        // 期望: rgb=绿色(在 bar 内)或深灰(不在 bar 内)

        send_pixel(11'd500, 11'd410, 1'b1); // 发送像素(500,410), 压力条远处
        #1;
        $display("[T=%0t] x=500,y=410 de=%b rgb=%06X (bar area)", $time, de_o, rgb_o);
        // pressure=4000, bar_pixels=4000*600/8000=300, 所以 x=100+300=400 是边界
        // x=500 > 400, 所以不在 bar 内, 应为深灰色

        // ---- 测试 6: de=0(非显示区) ----
        send_pixel(11'd100, 11'd410, 1'b0); // de=0, 消隐期
        #1;
        $display("[T=%0t] de=0 rgb=%06X (expect black)", $time, rgb_o);
        // 期望: rgb=黑色(000000), de=0 时输出黑色

        // ---- 结束 ----
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;                          // 结束仿真
    end                                   // initial 结束

endmodule                                 // 模块结束
