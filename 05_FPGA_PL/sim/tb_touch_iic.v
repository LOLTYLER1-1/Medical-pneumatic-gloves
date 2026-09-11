`timescale 1ns / 1ps

module tb_touch_iic;

    reg         clk;
    reg         rst_n;
    wire        scl_o;
    wire        sda_io;
    reg         tp_int_i;
    wire        tp_rst_o;
    wire [11:0] touch_x_o;
    wire [11:0] touch_y_o;
    wire        touch_valid_o;

    localparam CLK_HZ  = 32'd100_000_000;
    localparam SCL_DIV = CLK_HZ / (32'd400_000 * 4);

    touch_iic #(
        .CLK_FREQ_HZ(CLK_HZ),
        .SCL_FREQ_HZ(32'd400_000),
        .SCL_DIV(SCL_DIV),
        .POLL_MS(32'd1),
        .POLL_MAX(CLK_HZ / 1000)
    ) uut (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .scl_o         (scl_o),
        .sda_io        (sda_io),
        .tp_int_i      (tp_int_i),
        .tp_rst_o      (tp_rst_o),
        .touch_x_o     (touch_x_o),
        .touch_y_o     (touch_y_o),
        .touch_valid_o (touch_valid_o)
    );

    i2c_slave_bfm #(
        .SLAVE_ADDR(7'h5D)
    ) slave (
        .scl(scl_o),
        .sda(sda_io)
    );

    initial begin
        slave.mem[0] = 8'h34;
        slave.mem[1] = 8'h01;
        slave.mem[2] = 8'h56;
        slave.mem[3] = 8'h02;
    end

    initial begin
        $dumpfile("touch_iic.vcd");
        $dumpvars(0, tb_touch_iic);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("========================================");
        $display("  touch_iic Testbench");
        $display("  (POLL_MS=1 for fast sim)");
        $display("========================================");

        rst_n = 1'b0;
        tp_int_i = 1'b1;
        #100;
        $display("[T=%0t] Reset active, tp_rst_o=%b", $time, tp_rst_o);

        rst_n = 1'b1;
        #200;
        $display("[T=%0t] After reset, tp_rst_o=%b", $time, tp_rst_o);

        wait(tp_rst_o == 1'b1);
        $display("[T=%0t] Touch controller reset done", $time);

        #50000;
        $display("[T=%0t] Waiting for first IIC transaction...", $time);

        #2000000;
        $display("[T=%0t] After ~2ms, touch_x=%d touch_y=%d valid=%b",
                 $time, touch_x_o, touch_y_o, touch_valid_o);
        $display("  Expected: X=0x%03X (%d), Y=0x%03X (%d)",
                 12'h134, 12'h134, 12'h256, 12'h256);

        tp_int_i = 1'b0;
        #2000000;
        $display("[T=%0t] tp_int=0, touch_valid=%b (expect 1)", $time, touch_valid_o);

        tp_int_i = 1'b1;
        #2000000;
        $display("[T=%0t] tp_int=1, touch_valid=%b (expect 0)", $time, touch_valid_o);

        $display("========================================");
        $display("  Test complete! Check VCD for timing.");
        $display("========================================");
        $finish;
    end

endmodule
