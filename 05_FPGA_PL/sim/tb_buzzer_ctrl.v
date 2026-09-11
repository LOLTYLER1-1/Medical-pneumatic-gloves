`timescale 1ns / 1ps

module tb_buzzer_ctrl;

    reg  clk;
    reg  rst_n;
    reg  trigger_i;
    wire buzzer_o;

    localparam CLK_HZ = 32'd1_000_000;
    localparam BEEP_FREQ_HZ = 32'd1000;

    buzzer_ctrl #(
        .CLK_HZ      (CLK_HZ),
        .BEEP_FREQ_HZ(BEEP_FREQ_HZ)
    ) uut (
        .clk_i     (clk),
        .rst_n_i   (rst_n),
        .trigger_i (trigger_i),
        .buzzer_o  (buzzer_o)
    );

    initial begin
        $dumpfile("buzzer_ctrl.vcd");
        $dumpvars(0, tb_buzzer_ctrl);
    end

    initial clk = 0;
    always #500 clk = ~clk;

    initial begin
        $display("========================================");
        $display("  buzzer_ctrl Testbench");
        $display("  (CLK=1MHz, BEEP=1kHz for fast sim)");
        $display("========================================");

        rst_n = 1'b0; trigger_i = 1'b0;
        #2000;
        rst_n = 1'b1;
        #2000;

        $display("[T=%0t] trigger=0 -> buzzer=%b (expect 0)", $time, buzzer_o);

        trigger_i = 1'b1;
        #500000;
        $display("[T=%0t] trigger=1 after 0.5ms -> buzzer=%b", $time, buzzer_o);

        #500000;
        $display("[T=%0t] trigger=1 after 1ms (first half period) -> buzzer=%b", $time, buzzer_o);

        #500000;
        $display("[T=%0t] trigger=1 after 1.5ms -> buzzer=%b", $time, buzzer_o);

        #500000;
        $display("[T=%0t] trigger=1 after 2ms (should toggle) -> buzzer=%b", $time, buzzer_o);

        trigger_i = 1'b0;
        #1000;
        $display("[T=%0t] trigger=0 -> buzzer=%b (expect 0, counter reset)", $time, buzzer_o);

        #2000;
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
