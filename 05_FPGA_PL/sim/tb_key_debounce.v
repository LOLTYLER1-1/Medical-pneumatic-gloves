`timescale 1ns / 1ps

module tb_key_debounce;

    reg        clk;
    reg        rst_n;
    reg        key_raw_i;
    wire       key_clean_o;

    localparam CLK_FREQ_HZ = 32'd100_000_000;
    localparam DEBOUNCE_MS = 32'd1;
    localparam DEBOUNCE_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

    key_debounce #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (DEBOUNCE_MS),
        .DEBOUNCE_MAX(DEBOUNCE_MAX)
    ) uut (
        .clk_i       (clk),
        .rst_n_i     (rst_n),
        .key_raw_i   (key_raw_i),
        .key_clean_o (key_clean_o)
    );

    initial begin
        $dumpfile("key_debounce.vcd");
        $dumpvars(0, tb_key_debounce);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task key_bounce;
        begin
            key_raw_i = 1'b0; #100;
            key_raw_i = 1'b1; #80;
            key_raw_i = 1'b0; #120;
            key_raw_i = 1'b1; #60;
            key_raw_i = 1'b0;
        end
    endtask

    initial begin
        $display("========================================");
        $display("  key_debounce Testbench");
        $display("  (DEBOUNCE_MS=1 for fast sim)");
        $display("========================================");

        rst_n = 1'b0; key_raw_i = 1'b1;
        #20;
        rst_n = 1'b1;
        #10;
        $display("[T=%0t] Initial state -> key_clean=%b (expect 1)", $time, key_clean_o);

        $display("[T=%0t] Simulating key press with bounce...", $time);
        key_bounce;

        #2000000;
        $display("[T=%0t] After debounce period -> key_clean=%b (expect 0)", $time, key_clean_o);

        key_raw_i = 1'b1;
        #2000000;
        $display("[T=%0t] Key released -> key_clean=%b (expect 1)", $time, key_clean_o);

        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
