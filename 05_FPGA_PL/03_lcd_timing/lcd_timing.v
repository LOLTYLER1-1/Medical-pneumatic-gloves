`timescale 1ns / 1ps

module lcd_timing #(
    parameter H_SYNC   = 11'd128,
    parameter H_BACK   = 11'd88,
    parameter H_ACTIVE = 11'd800,
    parameter H_FRONT  = 11'd40,
    parameter H_TOTAL  = 11'd1056,

    parameter V_SYNC   = 11'd2,
    parameter V_BACK   = 11'd33,
    parameter V_ACTIVE = 11'd480,
    parameter V_FRONT  = 11'd10,
    parameter V_TOTAL  = 11'd525
)(
    input  wire        pclk_i,
    input  wire        rst_n_i,

    output wire        hsync_o,
    output wire        vsync_o,
    output wire        de_o,
    output wire [10:0] pixel_x_o,
    output wire [10:0] pixel_y_o
);

    reg [10:0] h_cnt;
    reg [10:0] v_cnt;

    always @(posedge pclk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            h_cnt <= 11'd0;
        else if (h_cnt == H_TOTAL - 1)
            h_cnt <= 11'd0;
        else
            h_cnt <= h_cnt + 11'd1;
    end

    always @(posedge pclk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            v_cnt <= 11'd0;
        else if (h_cnt == H_TOTAL - 1) begin
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 11'd0;
            else
                v_cnt <= v_cnt + 11'd1;
        end
    end

    assign hsync_o = (h_cnt < H_SYNC) ? 1'b0 : 1'b1;
    assign vsync_o = (v_cnt < V_SYNC) ? 1'b0 : 1'b1;

    wire h_active = (h_cnt >= (H_SYNC + H_BACK)) &&
                    (h_cnt <  (H_SYNC + H_BACK + H_ACTIVE));
    wire v_active = (v_cnt >= (V_SYNC + V_BACK)) &&
                    (v_cnt <  (V_SYNC + V_BACK + V_ACTIVE));

    assign de_o = h_active & v_active;

    assign pixel_x_o = h_active ? (h_cnt - (H_SYNC + H_BACK)) : 11'd0;
    assign pixel_y_o = v_active ? (v_cnt - (V_SYNC + V_BACK)) : 11'd0;

endmodule
