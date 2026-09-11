`timescale 1ns / 1ps

module tb_axi_lite_reg;

    reg         clk;
    reg         rst_n;
    reg  [15:0] pressure_kpa_i;
    reg  [2:0]  fsm_state_i;
    reg         safety_trigger_i;
    wire [15:0] pressure_kpa_o;
    wire [2:0]  fsm_state_o;
    wire        safety_trigger_o;

    axi_lite_reg uut (
        .clk_i            (clk),
        .rst_n_i          (rst_n),
        .pressure_kpa_i   (pressure_kpa_i),
        .fsm_state_i      (fsm_state_i),
        .safety_trigger_i (safety_trigger_i),
        .pressure_kpa_o   (pressure_kpa_o),
        .fsm_state_o      (fsm_state_o),
        .safety_trigger_o (safety_trigger_o)
    );

    initial begin
        $dumpfile("axi_lite_reg.vcd");
        $dumpvars(0, tb_axi_lite_reg);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("========================================");
        $display("  axi_lite_reg Testbench");
        $display("========================================");

        rst_n = 1'b0; pressure_kpa_i = 16'd0; fsm_state_i = 3'd0; safety_trigger_i = 1'b0;
        #20;
        rst_n = 1'b1;
        #10;
        $display("[T=%0t] After reset -> pressure=%d state=%d trigger=%b", $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);

        @(posedge clk);
        pressure_kpa_i = 16'd1234; fsm_state_i = 3'd2; safety_trigger_i = 1'b1;
        @(posedge clk);
        $display("[T=%0t] Input changed -> pressure=%d state=%d trigger=%b", $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);

        @(posedge clk);
        $display("[T=%0t] Next cycle   -> pressure=%d state=%d trigger=%b", $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);

        @(posedge clk);
        pressure_kpa_i = 16'd5678; fsm_state_i = 3'd4; safety_trigger_i = 1'b0;
        @(posedge clk);
        $display("[T=%0t] Input changed -> pressure=%d state=%d trigger=%b", $time, pressure_kpa_o, fsm_state_o, safety_trigger_o);

        #20;
        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
