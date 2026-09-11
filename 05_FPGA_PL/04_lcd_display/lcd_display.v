`timescale 1ns / 1ps

module lcd_display #(
    parameter IMG_W    = 11'd200,
    parameter IMG_H    = 11'd175,
    parameter IMG_X0   = 11'd300,
    parameter IMG_Y0   = 11'd152
)(
    input  wire        pclk_i,
    input  wire        rst_n_i,

    input  wire        hsync_i,
    input  wire        vsync_i,
    input  wire        de_i,
    input  wire [10:0] pixel_x_i,
    input  wire [10:0] pixel_y_i,

    input  wire [15:0] pressure_kpa_i,
    input  wire [2:0]  fsm_state_i,

    output reg         hsync_o,
    output reg         vsync_o,
    output reg         de_o,
    output reg  [23:0] rgb_o
);

    localparam ST_IDLE      = 3'd0;
    localparam ST_GRIP      = 3'd1;
    localparam ST_HOLD      = 3'd2;
    localparam ST_RELEASE   = 3'd3;
    localparam ST_EMERGENCY = 3'd4;

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

    reg [23:0] state_color;
    always @(*) begin
        case (fsm_state_i)
            ST_IDLE     : state_color = C_RED;
            ST_GRIP     : state_color = C_GREEN;
            ST_HOLD     : state_color = C_BLUE;
            ST_RELEASE  : state_color = C_ORANGE;
            ST_EMERGENCY: state_color = C_RED;
            default     : state_color = C_GRAY;
        endcase
    end

    wire [15:0] bar_pixels = (pressure_kpa_i * 600) / 8000;
    wire        in_bar     = (pixel_x_i >= 11'd100) &&
                             (pixel_x_i <  (11'd100 + bar_pixels[10:0]));

    /*=====================================================================
     * 压力数值显示 (2026-08-03 新增)
     * 在压力条上方黑带 (y360~400) 内显示 "XXX.XX KPA" 白色数字
     * 字库: 经典 5x7 点阵 (列格式, bit0=顶行), 放大4倍 = 20x28像素/字符
     * 起点 (100,364) 与压力条左对齐, 共 10 个字符位: d4 d3 d2 . d1 d0 _ K P A
     * 压力单位 0.01kPa: 整数部分 = d4d3d2, 小数部分 = d1d0
     *====================================================================*/
    localparam TXT_X0      = 11'd100;
    localparam TXT_Y0      = 11'd364;
    localparam GLYPH_BLANK = 4'd14;

    /* 16bit 二进制 -> 5 位 BCD (double-dabble: 左移+逢5加3, 16 轮组合逻辑) */
    reg [35:0] bcd_shift;
    integer    bi;
    always @(*) begin
        bcd_shift = {20'd0, pressure_kpa_i};
        for (bi = 0; bi < 16; bi = bi + 1) begin
            if (bcd_shift[19:16] >= 5) bcd_shift[19:16] = bcd_shift[19:16] + 3;
            if (bcd_shift[23:20] >= 5) bcd_shift[23:20] = bcd_shift[23:20] + 3;
            if (bcd_shift[27:24] >= 5) bcd_shift[27:24] = bcd_shift[27:24] + 3;
            if (bcd_shift[31:28] >= 5) bcd_shift[31:28] = bcd_shift[31:28] + 3;
            if (bcd_shift[35:32] >= 5) bcd_shift[35:32] = bcd_shift[35:32] + 3;
            bcd_shift = bcd_shift << 1;
        end
    end
    wire [3:0] bcd_d4 = bcd_shift[35:32];  /* kPa 百位 */
    wire [3:0] bcd_d3 = bcd_shift[31:28];  /* kPa 十位 */
    wire [3:0] bcd_d2 = bcd_shift[27:24];  /* kPa 个位 */
    wire [3:0] bcd_d1 = bcd_shift[23:20];  /* 小数 1 位 */
    wire [3:0] bcd_d0 = bcd_shift[19:16];  /* 小数 2 位 */

    /* 前导零消隐: d4=0 不显示; d4,d3 都为 0 时 d3 也不显示 (d2 个位恒显示) */
    wire [3:0] glyph_d4 = (bcd_d4 == 4'd0)                 ? GLYPH_BLANK : bcd_d4;
    wire [3:0] glyph_d3 = (bcd_d4 == 4'd0 && bcd_d3 == 4'd0) ? GLYPH_BLANK : bcd_d3;

    /* 5x7 字库: 返回某字符 5 列, [6:0]=col0 ... [34:28]=col4, bit0=顶行 */
    function [34:0] font5(input [3:0] glyph);
        case (glyph)
            4'd0 : font5 = {7'h3E, 7'h45, 7'h49, 7'h51, 7'h3E};
            4'd1 : font5 = {7'h40, 7'h40, 7'h7F, 7'h42, 7'h00};
            4'd2 : font5 = {7'h46, 7'h49, 7'h51, 7'h61, 7'h42};
            4'd3 : font5 = {7'h31, 7'h4B, 7'h45, 7'h41, 7'h21};
            4'd4 : font5 = {7'h10, 7'h7F, 7'h12, 7'h14, 7'h18};
            4'd5 : font5 = {7'h39, 7'h45, 7'h45, 7'h45, 7'h27};
            4'd6 : font5 = {7'h30, 7'h49, 7'h49, 7'h4A, 7'h3C};
            4'd7 : font5 = {7'h03, 7'h05, 7'h09, 7'h71, 7'h01};
            4'd8 : font5 = {7'h36, 7'h49, 7'h49, 7'h49, 7'h36};
            4'd9 : font5 = {7'h1E, 7'h29, 7'h49, 7'h49, 7'h06};
            4'd10: font5 = {7'h00, 7'h00, 7'h60, 7'h60, 7'h00};  /* '.'  */
            4'd11: font5 = {7'h41, 7'h22, 7'h14, 7'h08, 7'h7F};  /* 'K'  */
            4'd12: font5 = {7'h06, 7'h09, 7'h09, 7'h09, 7'h7F};  /* 'P'  */
            4'd13: font5 = {7'h7E, 7'h11, 7'h11, 7'h11, 7'h7E};  /* 'A'  */
            default: font5 = 35'd0;                              /* 空白 */
        endcase
    endfunction

    /* 文本带区域: 10 字符位 x 24px(20 字宽+4 间隙) = 240, 末位去尾隙 = 236 */
    wire        in_txt_band = (pixel_y_i >= TXT_Y0) && (pixel_y_i < TXT_Y0 + 11'd28) &&
                              (pixel_x_i >= TXT_X0) && (pixel_x_i < TXT_X0 + 11'd236);
    wire [10:0] txt_x  = pixel_x_i - TXT_X0;
    wire [10:0] txt_y  = pixel_y_i - TXT_Y0;
    wire [3:0]  slot   = txt_x / 24;           /* 第几个字符位 0~9 */
    wire [10:0] slot_x = txt_x % 24;           /* 字符位内 x 0~23 */
    wire        gap_px = (slot_x >= 11'd20);   /* 20~23 为字符间隙 */
    wire [2:0]  col5   = slot_x[4:0] / 4;      /* 字库列 0~4 */
    wire [2:0]  row7   = txt_y / 4;            /* 字库行 0~6 */

    /* 字符位 -> 字库索引 */
    reg [3:0] cur_glyph;
    always @(*) begin
        case (slot)
            4'd0   : cur_glyph = glyph_d4;
            4'd1   : cur_glyph = glyph_d3;
            4'd2   : cur_glyph = bcd_d2;
            4'd3   : cur_glyph = 4'd10;        /* '.' */
            4'd4   : cur_glyph = bcd_d1;
            4'd5   : cur_glyph = bcd_d0;
            4'd7   : cur_glyph = 4'd11;        /* 'K' */
            4'd8   : cur_glyph = 4'd12;        /* 'P' */
            4'd9   : cur_glyph = 4'd13;        /* 'A' */
            default: cur_glyph = GLYPH_BLANK;
        endcase
    end

    wire [34:0] glyph_cols = font5(cur_glyph);
    wire [6:0]  col_bits   = (glyph_cols >> (col5 * 7)) & 7'h7F;
    wire        txt_pixel  = in_txt_band && !gap_px && col_bits[row7];

    /* 按钮区域定义 */
    wire in_btn_grip   = (pixel_x_i >= 11'd50)  && (pixel_x_i < 11'd350) &&
                         (pixel_y_i >= 11'd430) && (pixel_y_i < 11'd470);
    wire in_btn_rel    = (pixel_x_i >= 11'd450) && (pixel_x_i < 11'd750) &&
                         (pixel_y_i >= 11'd430) && (pixel_y_i < 11'd470);
    wire in_btn_border = ((pixel_x_i >= 11'd50)  && (pixel_x_i < 11'd350) &&
                          ((pixel_y_i == 11'd430) || (pixel_y_i == 11'd469))) ||
                         (((pixel_x_i == 11'd50)  || (pixel_x_i == 11'd349)) &&
                          (pixel_y_i >= 11'd430) && (pixel_y_i < 11'd470)) ||
                         ((pixel_x_i >= 11'd450) && (pixel_x_i < 11'd750) &&
                          ((pixel_y_i == 11'd430) || (pixel_y_i == 11'd469))) ||
                         (((pixel_x_i == 11'd450) || (pixel_x_i == 11'd749)) &&
                          (pixel_y_i >= 11'd430) && (pixel_y_i < 11'd470));

    /* 顶部状态条边框 + 触摸方向标记 */
    wire in_status_bar    = (pixel_y_i < 11'd50);
    wire in_status_border = (pixel_y_i == 11'd49);
    /* 收缩标记：绿色状态条右上角白方块 */
    wire in_grip_marker   = (fsm_state_i == ST_GRIP)    &&
                            (pixel_x_i >= 11'd720) && (pixel_x_i < 11'd760) &&
                            (pixel_y_i >= 11'd10)  && (pixel_y_i < 11'd40);
    /* 舒张标记：橙色状态条左上角白方块 */
    wire in_rel_marker    = (fsm_state_i == ST_RELEASE) &&
                            (pixel_x_i >= 11'd40)  && (pixel_x_i < 11'd80)  &&
                            (pixel_y_i >= 11'd10)  && (pixel_y_i < 11'd40);

    reg [23:0] bg_color;
    always @(*) begin
        if (in_grip_marker || in_rel_marker)
            bg_color = C_WHITE;
        else if (in_status_border)
            bg_color = C_WHITE;
        else if (in_status_bar)
            bg_color = state_color;
        else if (pixel_y_i < 11'd360)
            bg_color = (pixel_x_i < 11'd400) ? C_LIGHTGRN : C_LIGHTORG;
        else if (pixel_y_i < 11'd400)
            bg_color = txt_pixel ? C_WHITE : C_BLACK;   /* 黑带内叠加压力数值 */
        else if (pixel_y_i < 11'd430) begin
            if ((pixel_x_i >= 11'd98) && (pixel_x_i < 11'd702)) begin
                if ((pixel_x_i == 11'd98) || (pixel_x_i == 11'd99) ||
                    (pixel_x_i == 11'd700) || (pixel_x_i == 11'd701))
                    bg_color = C_WHITE;
                else if (in_bar)
                    bg_color = C_GREEN;
                else
                    bg_color = C_DARKGRAY;
            end else begin
                bg_color = C_BLACK;
            end
        end else if (in_btn_border)
            bg_color = C_WHITE;
        else if (in_btn_grip)
            bg_color = C_GREEN;
        else if (in_btn_rel)
            bg_color = C_ORANGE;
        else
            bg_color = C_BLACK;
    end

    wire in_img = (pixel_x_i >= IMG_X0) && (pixel_x_i < (IMG_X0 + IMG_W)) &&
                  (pixel_y_i >= IMG_Y0) && (pixel_y_i < (IMG_Y0 + IMG_H));

    wire [10:0] img_x = pixel_x_i - IMG_X0;
    wire [10:0] img_y = pixel_y_i - IMG_Y0;
    wire [15:0] img_addr = img_y * IMG_W + img_x;

    wire [15:0] img_pixel_565;

    lcd_image_rom u_lcd_image_rom (
        .clka  (pclk_i),
        .addra (img_addr),
        .douta (img_pixel_565)
    );

    wire [7:0] img_r = {img_pixel_565[15:11], img_pixel_565[15:13]};
    wire [7:0] img_g = {img_pixel_565[10:5],  img_pixel_565[10:9]};
    wire [7:0] img_b = {img_pixel_565[4:0],   img_pixel_565[4:2]};
    wire [23:0] img_rgb888 = {img_r, img_g, img_b};

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
