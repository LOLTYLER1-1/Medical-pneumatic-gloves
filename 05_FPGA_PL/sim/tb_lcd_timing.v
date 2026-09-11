`timescale 1ns / 1ps

module tb_lcd_timing;

    reg         pclk;
    reg         rst_n;
    wire        hsync_o;
    wire        vsync_o;
    wire        de_o;
    wire [10:0] pixel_x_o;
    wire [10:0] pixel_y_o;

    localparam H_SYNC   = 11'd4;
    localparam H_BACK   = 11'd2;
    localparam H_ACTIVE = 11'd8;
    localparam H_FRONT  = 11'd2;
    localparam H_TOTAL  = 11'd16;

    localparam V_SYNC   = 11'd1;
    localparam V_BACK   = 11'd1;
    localparam V_ACTIVE = 11'd4;
    localparam V_FRONT  = 11'd1;
    localparam V_TOTAL  = 11'd7;

    lcd_timing #(
        .H_SYNC   (H_SYNC),
        .H_BACK   (H_BACK),
        .H_ACTIVE (H_ACTIVE),
        .H_FRONT  (H_FRONT),
        .H_TOTAL  (H_TOTAL),
        .V_SYNC   (V_SYNC),
        .V_BACK   (V_BACK),
        .V_ACTIVE (V_ACTIVE),
        .V_FRONT  (V_FRONT),
        .V_TOTAL  (V_TOTAL)
    ) uut (
        .pclk_i    (pclk),
        .rst_n_i   (rst_n),
        .hsync_o   (hsync_o),
        .vsync_o   (vsync_o),
        .de_o      (de_o),
        .pixel_x_o (pixel_x_o),
        .pixel_y_o (pixel_y_o)
    );

    initial begin
        $dumpfile("lcd_timing.vcd");
        $dumpvars(0, tb_lcd_timing);
    end

    initial pclk = 0;
    always #15 pclk = ~pclk;

    initial begin
        $display("========================================");
        $display("  lcd_timing Testbench");
        $display("  (Mini params: 16x7 frame, 8x4 active)");
        $display("========================================");

        rst_n = 1'b0;
        #50;
        rst_n = 1'b1;
        #20;

        $display("[T=%0t] Waiting for first frame...", $time);

        wait(vsync_o == 1'b0);
        $display("[T=%0t] VSync low (sync pulse)", $time);

        wait(vsync_o == 1'b1);
        $display("[T=%0t] VSync high (back porch + active)", $time);

        wait(de_o == 1'b1);
        $display("[T=%0t] DE=1, first active pixel: x=%d y=%d", $time, pixel_x_o, pixel_y_o);

        repeat(H_ACTIVE * V_ACTIVE) @(posedge pclk);
        #1;
        $display("[T=%0t] After all active pixels, last: x=%d y=%d de=%b", $time, pixel_x_o, pixel_y_o, de_o);

        wait(vsync_o == 1'b0);
        $display("[T=%0t] Second frame VSync low", $time);

        #100;
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
