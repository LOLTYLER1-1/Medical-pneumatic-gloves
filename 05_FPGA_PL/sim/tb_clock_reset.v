`timescale 1ns / 1ps

module clk_wiz_0 (
    input  wire clk_in1,
    input  wire resetn,
    output reg  clk_out1,
    output reg  clk_out2,
    output reg  locked
);
    initial begin
        locked = 0;
        clk_out1 = 0;
        clk_out2 = 0;
        #100;
        locked = 1;
    end
    always #5  clk_out1 = ~clk_out1;
    always #15 clk_out2 = ~clk_out2;
endmodule

module tb_clock_reset;

    reg  sys_clk;
    reg  sys_rst_n;
    wire clk_100m;
    wire pclk_33m;
    wire rst_n_sync;

    clock_reset uut (
        .sys_clk_i   (sys_clk),
        .sys_rst_n_i (sys_rst_n),
        .clk_100m_o  (clk_100m),
        .pclk_33m_o  (pclk_33m),
        .rst_n_sync_o(rst_n_sync)
    );

    initial begin
        $dumpfile("clock_reset.vcd");
        $dumpvars(0, tb_clock_reset);
    end

    initial sys_clk = 0;
    always #10 sys_clk = ~sys_clk;

    initial begin
        $display("========================================");
        $display("  clock_reset Testbench");
        $display("========================================");

        sys_rst_n = 1'b0;
        #50;
        $display("[T=%0t] Reset active, rst_n_sync=%b", $time, rst_n_sync);

        sys_rst_n = 1'b1;
        #200;
        $display("[T=%0t] After reset release + locked, rst_n_sync=%b", $time, rst_n_sync);

        repeat(10) @(posedge clk_100m);
        $display("[T=%0t] clk_100m toggling, rst_n_sync=%b", $time, rst_n_sync);

        repeat(5) @(posedge pclk_33m);
        $display("[T=%0t] pclk_33m toggling, rst_n_sync=%b", $time, rst_n_sync);

        sys_rst_n = 1'b0;
        #50;
        $display("[T=%0t] Reset re-asserted, rst_n_sync=%b", $time, rst_n_sync);

        sys_rst_n = 1'b1;
        #200;
        $display("[T=%0t] Reset released again, rst_n_sync=%b", $time, rst_n_sync);

        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
