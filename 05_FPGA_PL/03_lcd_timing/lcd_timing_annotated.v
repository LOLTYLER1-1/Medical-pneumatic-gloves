//=============================================================================
// File        : lcd_timing_annotated.v   ★教学版★
// 类比: Arduino 用 Adafruit_GFX 库写显示, 这里是从零做底层时序
// 原理: 像 CRT 电视的"电子枪扫描", 一行一行从左到右、从上到下
//       SYNC=同步脉冲, BACK=后肩(空白), ACTIVE=有效像素, FRONT=前肩(空白)
//=============================================================================

`timescale 1ns / 1ps

module lcd_timing #(
    parameter H_SYNC   = 11'd128,                       // 水平同步脉冲宽度 (像素时钟数)
    parameter H_BACK   = 11'd88,                        // 水平后肩
    parameter H_ACTIVE = 11'd800,                       // 水平有效像素 (实际显示宽度)
    parameter H_FRONT  = 11'd40,                        // 水平前肩
    parameter H_TOTAL  = 11'd1056,                      // 一行总时钟数 = 128+88+800+40

    parameter V_SYNC   = 11'd2,                         // 垂直同步脉冲行数
    parameter V_BACK   = 11'd33,                        // 垂直后肩
    parameter V_ACTIVE = 11'd480,                       // 垂直有效行数 (实际显示高度)
    parameter V_FRONT  = 11'd10,                        // 垂直前肩
    parameter V_TOTAL  = 11'd525                        // 一帧总行数 = 2+33+480+10
)(
    input  wire        pclk_i,                          // 像素时钟 33.33 MHz
    input  wire        rst_n_i,                         // 同步复位(低有效)

    output wire        hsync_o,                         // 水平同步(低有效)
    output wire        vsync_o,                         // 垂直同步(低有效)
    output wire        de_o,                            // 数据有效(高有效)
    output wire [10:0] pixel_x_o,                       // 当前显示列号 0~799
    output wire [10:0] pixel_y_o                        // 当前显示行号 0~479
);

    // === 水平计数器: 数当前是这一行的第几个像素时钟 ===
    reg [10:0] h_cnt;
    always @(posedge pclk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            h_cnt <= 11'd0;                             // 复位清零
        else if (h_cnt == H_TOTAL - 1)
            h_cnt <= 11'd0;                             // 数到 1055 回 0, 进入下一行
        else
            h_cnt <= h_cnt + 11'd1;                     // 每个像素时钟加 1
    end

    // === 垂直计数器: 每一行结束(h_cnt 回 0 前)累加一次 ===
    reg [10:0] v_cnt;
    always @(posedge pclk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            v_cnt <= 11'd0;
        else if (h_cnt == H_TOTAL - 1) begin            // 这一行结束了
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 11'd0;                         // 整帧结束, 回顶
            else
                v_cnt <= v_cnt + 11'd1;
        end
    end

    // === 输出: 同步信号 (低有效) ===
    // 当 h_cnt < 128 时, 产生水平同步脉冲(拉低)
    assign hsync_o = (h_cnt < H_SYNC) ? 1'b0 : 1'b1;
    assign vsync_o = (v_cnt < V_SYNC) ? 1'b0 : 1'b1;

    // === 有效区判断 ===
    // 水平: 跳过 SYNC + BACK 后的 800 个像素是有效
    wire h_active = (h_cnt >= (H_SYNC + H_BACK)) &&
                    (h_cnt <  (H_SYNC + H_BACK + H_ACTIVE));
    // 垂直: 跳过 SYNC + BACK 后的 480 行是有效
    wire v_active = (v_cnt >= (V_SYNC + V_BACK)) &&
                    (v_cnt <  (V_SYNC + V_BACK + V_ACTIVE));

    assign de_o = h_active & v_active;                  // DE 高 = 屏幕在显示有效像素

    // === 像素坐标(只在有效区里有意义) ===
    assign pixel_x_o = h_active ? (h_cnt - (H_SYNC + H_BACK)) : 11'd0;
    assign pixel_y_o = v_active ? (v_cnt - (V_SYNC + V_BACK)) : 11'd0;

endmodule
