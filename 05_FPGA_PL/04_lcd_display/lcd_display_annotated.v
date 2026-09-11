//=============================================================================
// File        : lcd_display_annotated.v   ★教学版★
// 类比: Arduino 用 tft.drawBitmap() 一次画一张图
//       这里没有 framebuffer, 每个像素扫描到时从 ROM 取颜色
//
// BROM 时序对齐:
//   BROM 默认 1 拍延迟 -> 我们用 2 级 pipeline 让所有信号同步
//   pipeline 第1拍: 保存 hsync/vsync/de/in_img/bg_color (BROM 内部寄存地址)
//   pipeline 第2拍: BROM 输出有效 + 我们寄存最终 rgb_o
//=============================================================================

`timescale 1ns / 1ps

module lcd_display #(
    parameter IMG_W    = 11'd200,                       // 图片宽 200 像素
    parameter IMG_H    = 11'd175,                       // 图片高 175 像素
    parameter IMG_X0   = 11'd300,                       // 屏幕中心: x_start = (800-200)/2
    parameter IMG_Y0   = 11'd152                        // y_start = (480-175)/2
)(
    input  wire        pclk_i,                          // 像素时钟 33.33 MHz
    input  wire        rst_n_i,                         // 同步复位

    // 来自 lcd_timing 的信号 (原始)
    input  wire        hsync_i,
    input  wire        vsync_i,
    input  wire        de_i,
    input  wire [10:0] pixel_x_i,
    input  wire [10:0] pixel_y_i,

    input  wire [15:0] pressure_kpa_i,
    input  wire [2:0]  fsm_state_i,

    // 经 2 拍延迟后输出给 LCD (与 BROM 同步)
    output reg         hsync_o,
    output reg         vsync_o,
    output reg         de_o,
    output reg  [23:0] rgb_o
);

    // === 状态码 ===
    localparam ST_IDLE      = 3'd0;
    localparam ST_GRIP      = 3'd1;
    localparam ST_HOLD      = 3'd2;
    localparam ST_RELEASE   = 3'd3;
    localparam ST_EMERGENCY = 3'd4;

    // === 颜色调色板 ===
    localparam C_BLACK    = 24'h000000;
    localparam C_WHITE    = 24'hFFFFFF;
    localparam C_GRAY     = 24'h606060;
    localparam C_RED      = 24'hFF2020;
    localparam C_GREEN    = 24'h20C040;
    localparam C_LIGHTGRN = 24'hA0E0A0;
    localparam C_BLUE     = 24'h2080FF;
    localparam C_ORANGE   = 24'hFF8000;
    localparam C_LIGHTORG = 24'hFFD0A0;
    localparam C_DARKGRAY = 24'h303030;

    // === 状态颜色 ===
    reg [23:0] state_color;
    always @(*) begin
        case (fsm_state_i)
            ST_IDLE     : state_color = C_GRAY;
            ST_GRIP     : state_color = C_GREEN;
            ST_HOLD     : state_color = C_BLUE;
            ST_RELEASE  : state_color = C_ORANGE;
            ST_EMERGENCY: state_color = C_RED;
            default     : state_color = C_GRAY;
        endcase
    end

    // === 压力条 ===
    wire [15:0] bar_pixels = (pressure_kpa_i * 600) / 8000;
    wire        in_bar     = (pixel_x_i >= 11'd100) &&
                             (pixel_x_i <  (11'd100 + bar_pixels[10:0]));

    // === 压力数值显示 (2026-08-03 新增) ===
    // 在压力条上方黑带 (y360~400) 显示 "XXX.XX KPA" 白色数字
    // 字库: 经典 5x7 点阵 (列格式, bit0=顶行), 放大4倍 = 20x28像素/字符
    localparam TXT_X0      = 11'd100;         // 文本左上角 x (与压力条左对齐)
    localparam TXT_Y0      = 11'd364;         // 文本左上角 y (黑带 y360~400 内)
    localparam GLYPH_BLANK = 4'd14;           // 空白字符的字库索引

    // --- 16bit 二进制 -> 5 位 BCD (double-dabble 左移+逢5加3, 16 轮) ---
    reg [35:0] bcd_shift;                     // 高20位=BCD, 低16位=二进制原值
    integer    bi;
    always @(*) begin
        bcd_shift = {20'd0, pressure_kpa_i};  // 初始: BCD 清 0, 装入二进制
        for (bi = 0; bi < 16; bi = bi + 1) begin
            if (bcd_shift[19:16] >= 5) bcd_shift[19:16] = bcd_shift[19:16] + 3;  // 个位逢5加3
            if (bcd_shift[23:20] >= 5) bcd_shift[23:20] = bcd_shift[23:20] + 3;  // 十位
            if (bcd_shift[27:24] >= 5) bcd_shift[27:24] = bcd_shift[27:24] + 3;  // 百位
            if (bcd_shift[31:28] >= 5) bcd_shift[31:28] = bcd_shift[31:28] + 3;  // 千位
            if (bcd_shift[35:32] >= 5) bcd_shift[35:32] = bcd_shift[35:32] + 3;  // 万位
            bcd_shift = bcd_shift << 1;       // 左移 1 位, 下一轮
        end
    end
    wire [3:0] bcd_d4 = bcd_shift[35:32];     // 压力(0.01kPa)万位 = kPa 百位
    wire [3:0] bcd_d3 = bcd_shift[31:28];     // 千位 = kPa 十位
    wire [3:0] bcd_d2 = bcd_shift[27:24];     // 百位 = kPa 个位
    wire [3:0] bcd_d1 = bcd_shift[23:20];     // 十位 = 小数第 1 位
    wire [3:0] bcd_d0 = bcd_shift[19:16];     // 个位 = 小数第 2 位

    // --- 前导零消隐: " 50.00" 而不是 "050.00" ---
    wire [3:0] glyph_d4 = (bcd_d4 == 4'd0)                   ? GLYPH_BLANK : bcd_d4;
    wire [3:0] glyph_d3 = (bcd_d4 == 4'd0 && bcd_d3 == 4'd0) ? GLYPH_BLANK : bcd_d3;

    // --- 5x7 字库函数: 输入字符索引, 输出 5 列点阵 [6:0]=col0..[34:28]=col4 ---
    function [34:0] font5(input [3:0] glyph);
        case (glyph)
            4'd0 : font5 = {7'h3E, 7'h45, 7'h49, 7'h51, 7'h3E};  // '0'
            4'd1 : font5 = {7'h40, 7'h40, 7'h7F, 7'h42, 7'h00};  // '1'
            4'd2 : font5 = {7'h46, 7'h49, 7'h51, 7'h61, 7'h42};  // '2'
            4'd3 : font5 = {7'h31, 7'h4B, 7'h45, 7'h41, 7'h21};  // '3'
            4'd4 : font5 = {7'h10, 7'h7F, 7'h12, 7'h14, 7'h18};  // '4'
            4'd5 : font5 = {7'h39, 7'h45, 7'h45, 7'h45, 7'h27};  // '5'
            4'd6 : font5 = {7'h30, 7'h49, 7'h49, 7'h4A, 7'h3C};  // '6'
            4'd7 : font5 = {7'h03, 7'h05, 7'h09, 7'h71, 7'h01};  // '7'
            4'd8 : font5 = {7'h36, 7'h49, 7'h49, 7'h49, 7'h36};  // '8'
            4'd9 : font5 = {7'h1E, 7'h29, 7'h49, 7'h49, 7'h06};  // '9'
            4'd10: font5 = {7'h00, 7'h00, 7'h60, 7'h60, 7'h00};  // '.'
            4'd11: font5 = {7'h41, 7'h22, 7'h14, 7'h08, 7'h7F};  // 'K'
            4'd12: font5 = {7'h06, 7'h09, 7'h09, 7'h09, 7'h7F};  // 'P'
            4'd13: font5 = {7'h7E, 7'h11, 7'h11, 7'h11, 7'h7E};  // 'A'
            default: font5 = 35'd0;                              // 空白
        endcase
    endfunction

    // --- 文本带区域与字符内坐标 ---
    wire        in_txt_band = (pixel_y_i >= TXT_Y0) && (pixel_y_i < TXT_Y0 + 11'd28) &&
                              (pixel_x_i >= TXT_X0) && (pixel_x_i < TXT_X0 + 11'd236);
    wire [10:0] txt_x  = pixel_x_i - TXT_X0;  // 文本带内 x 0~235
    wire [10:0] txt_y  = pixel_y_i - TXT_Y0;  // 文本带内 y 0~27
    wire [3:0]  slot   = txt_x / 24;          // 第几个字符位 (24px/位) 0~9
    wire [10:0] slot_x = txt_x % 24;          // 字符位内 x 0~23
    wire        gap_px = (slot_x >= 11'd20);  // 20~23 是字符间隙, 不画
    wire [2:0]  col5   = slot_x[4:0] / 4;     // 字库列 0~4 (x 放大4倍)
    wire [2:0]  row7   = txt_y / 4;           // 字库行 0~6 (y 放大4倍)

    // --- 字符位 -> 字库索引 (d4 d3 d2 . d1 d0 空 K P A) ---
    reg [3:0] cur_glyph;
    always @(*) begin
        case (slot)
            4'd0   : cur_glyph = glyph_d4;    // kPa 百位 (可消隐)
            4'd1   : cur_glyph = glyph_d3;    // kPa 十位 (可消隐)
            4'd2   : cur_glyph = bcd_d2;      // kPa 个位
            4'd3   : cur_glyph = 4'd10;       // 小数点
            4'd4   : cur_glyph = bcd_d1;      // 小数第 1 位
            4'd5   : cur_glyph = bcd_d0;      // 小数第 2 位
            4'd7   : cur_glyph = 4'd11;       // 'K'
            4'd8   : cur_glyph = 4'd12;       // 'P'
            4'd9   : cur_glyph = 4'd13;       // 'A'
            default: cur_glyph = GLYPH_BLANK; // slot6 及其余: 空白
        endcase
    end

    // --- 取当前像素: 字库列移位选中, 再按行取 bit ---
    wire [34:0] glyph_cols = font5(cur_glyph);            // 当前字符 5 列点阵
    wire [6:0]  col_bits   = (glyph_cols >> (col5 * 7)) & 7'h7F;  // 当前列 7 个像素
    wire        txt_pixel  = in_txt_band && !gap_px && col_bits[row7];

    // === 背景颜色生成 (UI 各区域) ===
    reg [23:0] bg_color;
    always @(*) begin
        if (pixel_y_i < 11'd50)                          // 顶部状态栏
            bg_color = state_color;
        else if (pixel_y_i < 11'd360)                    // 中部按钮区
            bg_color = (pixel_x_i < 11'd400) ? C_LIGHTGRN : C_LIGHTORG;
        else if (pixel_y_i < 11'd400)                    // 分隔黑条
            bg_color = txt_pixel ? C_WHITE : C_BLACK;    // 黑带内叠加压力数值
        else if (pixel_y_i < 11'd450) begin              // 压力条
            if ((pixel_x_i >= 11'd98) && (pixel_x_i < 11'd702)) begin
                if ((pixel_x_i == 11'd98) || (pixel_x_i == 11'd99) ||
                    (pixel_x_i == 11'd700) || (pixel_x_i == 11'd701))
                    bg_color = C_WHITE;                  // 左右白边框
                else if (in_bar)
                    bg_color = C_GREEN;                  // 已充压
                else
                    bg_color = C_DARKGRAY;               // 空槽
            end else begin
                bg_color = C_BLACK;
            end
        end else
            bg_color = C_BLACK;
    end

    // === 图片区域判定 + 地址计算 ===
    wire in_img = (pixel_x_i >= IMG_X0) && (pixel_x_i < (IMG_X0 + IMG_W)) &&
                  (pixel_y_i >= IMG_Y0) && (pixel_y_i < (IMG_Y0 + IMG_H));

    wire [10:0] img_x = pixel_x_i - IMG_X0;              // 图片内 x 0~199
    wire [10:0] img_y = pixel_y_i - IMG_Y0;              // 图片内 y 0~174
    wire [15:0] img_addr = img_y * IMG_W + img_x;        // ROM 地址 0~34999 (需 16 位)

    // === BROM 例化 (Block Memory Generator IP) ===
    wire [15:0] img_pixel_565;
    lcd_image_rom u_lcd_image_rom (
        .clka  (pclk_i),                                 // 同步像素时钟
        .addra (img_addr),                               // 15-bit 地址
        .douta (img_pixel_565)                           // 16-bit RGB565 输出(1拍延迟)
    );

    // === RGB565 → RGB888 转换 ===
    // R5 → R8: 高 5 位 + 重复高 3 位 (保持亮度)
    wire [7:0] img_r = {img_pixel_565[15:11], img_pixel_565[15:13]};
    wire [7:0] img_g = {img_pixel_565[10:5],  img_pixel_565[10:9]};
    wire [7:0] img_b = {img_pixel_565[4:0],   img_pixel_565[4:2]};
    wire [23:0] img_rgb888 = {img_r, img_g, img_b};

    // === pipeline 第 1 级寄存器 (对齐 BROM 内部地址寄存) ===
    reg        hsync_d1, vsync_d1, de_d1, in_img_d1;
    reg [23:0] bg_color_d1;
    always @(posedge pclk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            hsync_d1    <= 1'b1;
            vsync_d1    <= 1'b1;
            de_d1       <= 1'b0;
            in_img_d1   <= 1'b0;
            bg_color_d1 <= C_BLACK;
        end else begin
            hsync_d1    <= hsync_i;
            vsync_d1    <= vsync_i;
            de_d1       <= de_i;
            in_img_d1   <= in_img;
            bg_color_d1 <= bg_color;
        end
    end

    // === pipeline 第 2 级寄存器 (与 BROM 输出对齐) ===
    always @(posedge pclk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            hsync_o <= 1'b1;
            vsync_o <= 1'b1;
            de_o    <= 1'b0;
            rgb_o   <= C_BLACK;
        end else begin
            hsync_o <= hsync_d1;
            vsync_o <= vsync_d1;
            de_o    <= de_d1;
            rgb_o   <= in_img_d1 ? img_rgb888 : bg_color_d1;
        end
    end

endmodule
