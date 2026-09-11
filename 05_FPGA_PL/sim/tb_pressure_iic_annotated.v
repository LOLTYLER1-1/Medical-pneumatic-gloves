`timescale 1ns / 1ps

module tb_pressure_iic;

    reg         clk;
    reg         rst_n;
    wire        scl_o;
    wire        sda_io;
    wire [15:0] pressure_kpa_o;

    localparam CLK_HZ  = 32'd100_000_000;
    localparam SCL_DIV = CLK_HZ / (32'd100_000 * 4);

    pressure_iic #(
        .CLK_FREQ_HZ(CLK_HZ),
        .SCL_FREQ_HZ(32'd100_000),
        .SCL_DIV(SCL_DIV),
        .CONV_MS(32'd1),
        .CONV_MAX(CLK_HZ / 1000),
        .POLL_MS(32'd2),
        .POLL_MAX(CLK_HZ / 500)
    ) uut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .scl_o          (scl_o),
        .sda_io         (sda_io),
        .pressure_kpa_o (pressure_kpa_o)
    );

    i2c_slave_bfm #(
        .SLAVE_ADDR(7'h6D)
    ) slave (
        .scl(scl_o),
        .sda(sda_io)
    );

    initial begin
        slave.mem[0] = 8'h12;
        slave.mem[1] = 8'h34;
        slave.mem[2] = 8'h56;
    end

    initial begin
        $dumpfile("pressure_iic.vcd");
        $dumpvars(0, tb_pressure_iic);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("========================================");
        $display("  pressure_iic Testbench");
        $display("  (CONV_MS=1, POLL_MS=2 for fast sim)");
        $display("========================================");

        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
        #100;
        $display("[T=%0t] Reset released, waiting for IIC transactions...", $time);

        #5000000;
        $display("[T=%0t] After ~5ms, pressure_kpa=%d", $time, pressure_kpa_o);
        $display("  ADC=0x123456=1193046, Expected=1193046*100/8389=%d",
                 (32'd1193046 * 32'd100) / 32'd8389);

        #5000000;
        $display("[T=%0t] After ~10ms, pressure_kpa=%d", $time, pressure_kpa_o);

        $display("========================================");
        $display("  Test complete! Check VCD for timing.");
        $display("========================================");
        $finish;
    end

endmodule
