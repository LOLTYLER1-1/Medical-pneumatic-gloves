`timescale 1ns / 1ps

module tb_pwm_ctrl;

    reg        clk;
    reg        rst_n;
    reg  [7:0] duty_i;
    reg        enable_i;
    wire       pwm_o;

    localparam RAMP_FAST = 32'd10;

    pwm_ctrl #(
        .WIDTH(8),
        .RAMP_CYC_PER_STEP(RAMP_FAST)
    ) uut (
        .clk_i    (clk),
        .rst_n_i  (rst_n),
        .duty_i   (duty_i),
        .enable_i (enable_i),
        .pwm_o    (pwm_o)
    );

    initial begin
        $dumpfile("pwm_ctrl.vcd");
        $dumpvars(0, tb_pwm_ctrl);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("========================================");
        $display("  pwm_ctrl Testbench");
        $display("  (RAMP_CYC_PER_STEP=10 for fast sim)");
        $display("========================================");

        rst_n = 1'b0; duty_i = 8'd100; enable_i = 1'b0;
        #20;
        rst_n = 1'b1;
        #10;
        $display("[T=%0t] enable=0 -> pwm=%b", $time, pwm_o);

        enable_i = 1'b1;
        repeat(20) @(posedge clk);
        $display("[T=%0t] enable=1, duty=100, after 20 cycles -> pwm=%b", $time, pwm_o);

        repeat(2560) @(posedge clk);
        $display("[T=%0t] After ramp complete -> pwm=%b", $time, pwm_o);

        duty_i = 8'd50;
        repeat(20) @(posedge clk);
        $display("[T=%0t] duty changed to 50 -> pwm=%b", $time, pwm_o);

        enable_i = 1'b0;
        @(posedge clk);
        $display("[T=%0t] enable=0 -> pwm=%b (expect 0)", $time, pwm_o);

        duty_i = 8'd200;
        enable_i = 1'b1;
        repeat(3000) @(posedge clk);
        $display("[T=%0t] duty=200, ramp done -> pwm=%b", $time, pwm_o);

        #100;
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
