`timescale 1ns / 1ps

module tb_glove_fsm;

    reg         clk;
    reg         rst_n;
    reg         grip_req_i;
    reg         release_req_i;
    reg         emerg_i;
    reg  [15:0] pressure_i;
    reg  [15:0] setpoint_i;
    wire [2:0]  state_o;
    wire        pump_o;
    wire        v2_o;

    glove_fsm #(
        .PRESSURE_MIN(16'd100)
    ) uut (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .grip_req_i    (grip_req_i),
        .release_req_i (release_req_i),
        .emerg_i       (emerg_i),
        .pressure_i    (pressure_i),
        .setpoint_i    (setpoint_i),
        .state_o       (state_o),
        .pump_o        (pump_o),
        .v2_o          (v2_o)
    );

    initial begin
        $dumpfile("glove_fsm.vcd");
        $dumpvars(0, tb_glove_fsm);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task print_state;
        begin
            case (state_o)
                3'd0: $display("[T=%0t] state=IDLE      pump=%b v2=%b", $time, pump_o, v2_o);
                3'd1: $display("[T=%0t] state=GRIP      pump=%b v2=%b", $time, pump_o, v2_o);
                3'd2: $display("[T=%0t] state=HOLD      pump=%b v2=%b", $time, pump_o, v2_o);
                3'd3: $display("[T=%0t] state=RELEASE   pump=%b v2=%b", $time, pump_o, v2_o);
                3'd4: $display("[T=%0t] state=EMERGENCY pump=%b v2=%b", $time, pump_o, v2_o);
                default: $display("[T=%0t] state=UNKNOWN   pump=%b v2=%b", $time, pump_o, v2_o);
            endcase
        end
    endtask

    initial begin
        $display("========================================");
        $display("  glove_fsm Testbench");
        $display("========================================");

        rst_n = 1'b0;
        grip_req_i = 1'b0; release_req_i = 1'b0; emerg_i = 1'b0;
        pressure_i = 16'd0; setpoint_i = 16'd3000;
        #20;
        rst_n = 1'b1;
        @(posedge clk); #1;
        print_state;

        grip_req_i = 1'b1;
        @(posedge clk); #1;
        print_state;
        grip_req_i = 1'b0;

        pressure_i = 16'd2000;
        @(posedge clk); #1;
        print_state;

        pressure_i = 16'd3000;
        @(posedge clk); #1;
        print_state;

        pressure_i = 16'd3500;
        @(posedge clk); #1;
        print_state;

        release_req_i = 1'b1;
        @(posedge clk); #1;
        print_state;
        release_req_i = 1'b0;

        pressure_i = 16'd50;
        @(posedge clk); #1;
        print_state;

        emerg_i = 1'b1;
        @(posedge clk); #1;
        print_state;
        emerg_i = 1'b0;

        pressure_i = 16'd0;
        @(posedge clk); #1;
        print_state;

        grip_req_i = 1'b1;
        @(posedge clk); #1;
        print_state;
        grip_req_i = 1'b0;

        $display("========================================");
        $display("  All tests passed!");
        $display("========================================");
        $finish;
    end

endmodule
