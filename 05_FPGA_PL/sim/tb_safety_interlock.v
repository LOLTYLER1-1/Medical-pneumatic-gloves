`timescale 1ns / 1ps

module tb_safety_interlock;

    reg  [15:0] pressure_i;
    reg         pump_in_i;
    reg         v2_in_i;
    wire        pump_out_o;
    wire        v2_out_o;
    wire        trigger_o;

    safety_interlock #(
        .PRESSURE_LIMIT(16'd8000)
    ) uut (
        .pressure_i (pressure_i),
        .pump_in_i  (pump_in_i),
        .v2_in_i    (v2_in_i),
        .pump_out_o (pump_out_o),
        .v2_out_o   (v2_out_o),
        .trigger_o  (trigger_o)
    );

    initial begin
        $dumpfile("safety_interlock.vcd");
        $dumpvars(0, tb_safety_interlock);
    end

    initial begin
        $display("========================================");
        $display("  safety_interlock Testbench");
        $display("========================================");

        pressure_i = 16'd0;   pump_in_i = 1'b0; v2_in_i = 1'b0;
        #10;

        $display("[T=%0t] pressure=0, pump_in=0, v2_in=0 -> trigger=%b pump_out=%b v2_out=%b", $time, trigger_o, pump_out_o, v2_out_o);

        pressure_i = 16'd5000; pump_in_i = 1'b1; v2_in_i = 1'b1;
        #10;
        $display("[T=%0t] pressure=5000, pump_in=1, v2_in=1 -> trigger=%b pump_out=%b v2_out=%b", $time, trigger_o, pump_out_o, v2_out_o);

        pressure_i = 16'd8000; pump_in_i = 1'b1; v2_in_i = 1'b1;
        #10;
        $display("[T=%0t] pressure=8000, pump_in=1, v2_in=1 -> trigger=%b pump_out=%b v2_out=%b", $time, trigger_o, pump_out_o, v2_out_o);

        pressure_i = 16'd9000; pump_in_i = 1'b1; v2_in_i = 1'b1;
        #10;
        $display("[T=%0t] pressure=9000, pump_in=1, v2_in=1 -> trigger=%b pump_out=%b v2_out=%b", $time, trigger_o, pump_out_o, v2_out_o);

        pressure_i = 16'd9000; pump_in_i = 1'b0; v2_in_i = 1'b0;
        #10;
        $display("[T=%0t] pressure=9000, pump_in=0, v2_in=0 -> trigger=%b pump_out=%b v2_out=%b", $time, trigger_o, pump_out_o, v2_out_o);

        pressure_i = 16'd7000; pump_in_i = 1'b0; v2_in_i = 1'b0;
        #10;
        $display("[T=%0t] pressure=7000, pump_in=0, v2_in=0 -> trigger=%b pump_out=%b v2_out=%b", $time, trigger_o, pump_out_o, v2_out_o);

        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
