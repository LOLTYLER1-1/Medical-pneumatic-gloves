`timescale 1ns / 1ps

module lcd_image_rom (
    input  wire        clka,
    input  wire [15:0] addra,
    output reg  [15:0] douta
);
    always @(posedge clka) begin
        douta <= {addra[4:0], addra[9:5], addra[14:10]};
    end
endmodule

module tb_lcd_display;

    reg         pclk;
    reg         rst_n;
    reg         hsync_i;
    reg         vsync_i;
    reg         de_i;
    reg  [10:0] pixel_x_i;
    reg  [10:0] pixel_y_i;
    reg  [15:0] pressure_kpa_i;
    reg  [2:0]  fsm_state_i;
    wire        hsync_o;
    wire        vsync_o;
    wire        de_o;
    wire [23:0] rgb_o;

    lcd_display uut (
        .pclk_i         (pclk),
        .rst_n_i        (rst_n),
        .hsync_i        (hsync_i),
        .vsync_i        (vsync_i),
        .de_i           (de_i),
        .pixel_x_i      (pixel_x_i),
        .pixel_y_i      (pixel_y_i),
        .pressure_kpa_i (pressure_kpa_i),
        .fsm_state_i    (fsm_state_i),
        .hsync_o        (hsync_o),
        .vsync_o        (vsync_o),
        .de_o           (de_o),
        .rgb_o          (rgb_o)
    );

    initial begin
        $dumpfile("lcd_display.vcd");
        $dumpvars(0, tb_lcd_display);
    end

    initial pclk = 0;
    always #15 pclk = ~pclk;

    task send_pixel;
        input [10:0] x;
        input [10:0] y;
        input        active;
        begin
            pixel_x_i = x;
            pixel_y_i = y;
            de_i = active;
            hsync_i = 1'b1;
            vsync_i = 1'b1;
            @(posedge pclk);
        end
    endtask

    initial begin
        $display("========================================");
        $display("  lcd_display Testbench");
        $display("========================================");

        rst_n = 1'b0;
        hsync_i = 1'b1; vsync_i = 1'b1; de_i = 1'b0;
        pixel_x_i = 0; pixel_y_i = 0;
        pressure_kpa_i = 16'd4000;
        fsm_state_i = 3'd1;
        #50;
        rst_n = 1'b1;
        #30;

        $display("[T=%0t] Test: top bar (state color)", $time);
        send_pixel(11'd100, 11'd10, 1'b1);
        #1;
        $display("[T=%0t] x=100,y=10 de=%b rgb=%06X (expect green for GRIP)", $time, de_o, rgb_o);

        send_pixel(11'd100, 11'd100, 1'b1);
        #1;
        $display("[T=%0t] x=100,y=100 de=%b rgb=%06X (expect LIGHTGRN)", $time, de_o, rgb_o);

        send_pixel(11'd500, 11'd100, 1'b1);
        #1;
        $display("[T=%0t] x=500,y=100 de=%b rgb=%06X (expect LIGHTORG)", $time, de_o, rgb_o);

        $display("[T=%0t] Test: image region", $time);
        send_pixel(11'd300, 11'd152, 1'b1);
        #1;
        $display("[T=%0t] x=300,y=152 de=%b rgb=%06X (image pixel)", $time, de_o, rgb_o);

        $display("[T=%0t] Test: pressure bar area", $time);
        send_pixel(11'd100, 11'd410, 1'b1);
        #1;
        $display("[T=%0t] x=100,y=410 de=%b rgb=%06X (bar area)", $time, de_o, rgb_o);

        send_pixel(11'd500, 11'd410, 1'b1);
        #1;
        $display("[T=%0t] x=500,y=410 de=%b rgb=%06X (bar area)", $time, de_o, rgb_o);

        send_pixel(11'd100, 11'd410, 1'b0);
        #1;
        $display("[T=%0t] de=0 rgb=%06X (expect black)", $time, rgb_o);

        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
