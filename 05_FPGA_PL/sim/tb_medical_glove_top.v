`timescale 1ns / 1ps

module clk_wiz_0 (
    input  wire clk_in1,
    input  wire resetn,
    output reg  clk_out1,
    output reg  clk_out2,
    output reg  locked
);
    initial begin locked = 0; clk_out1 = 0; clk_out2 = 0; #100; locked = 1; end
    always #5  clk_out1 = ~clk_out1;
    always #15 clk_out2 = ~clk_out2;
endmodule

module lcd_image_rom (
    input  wire        clka,
    input  wire [15:0] addra,
    output reg  [15:0] douta
);
    always @(posedge clka) douta <= {addra[4:0], addra[9:5], addra[14:10]};
endmodule

module tb_medical_glove_top;

    reg         sys_clk;
    reg         sys_rst_n;
    reg         emerg_key_i;
    wire [23:0] lcd_rgb_o;
    wire        lcd_hsync_o;
    wire        lcd_vsync_o;
    wire        lcd_de_o;
    wire        lcd_pclk_o;
    wire        lcd_bl_o;
    wire        tp_scl_o;
    wire        tp_sda_io;
    wire        tp_int_i;
    wire        tp_rst_o;
    wire        pres_scl_o;
    wire        pres_sda_io;
    wire        pump_o;
    wire        valve_v2_o;
    wire        led_status_o;
    wire        buzzer_o;
    reg         grip_req_i;
    reg         release_req_i;
    reg  [15:0] pressure_setpoint_i;
    wire [15:0] pressure_kpa_o;
    wire [2:0]  fsm_state_o;
    wire        safety_trigger_o;
    wire [11:0] touch_x_o;
    wire [11:0] touch_y_o;
    wire        touch_valid_o;

    medical_glove_top uut (
        .sys_clk_i         (sys_clk),
        .sys_rst_n_i       (sys_rst_n),
        .emerg_key_i       (emerg_key_i),
        .lcd_rgb_o         (lcd_rgb_o),
        .lcd_hsync_o       (lcd_hsync_o),
        .lcd_vsync_o       (lcd_vsync_o),
        .lcd_de_o          (lcd_de_o),
        .lcd_pclk_o        (lcd_pclk_o),
        .lcd_bl_o          (lcd_bl_o),
        .tp_sda_io         (tp_sda_io),
        .tp_scl_o          (tp_scl_o),
        .tp_int_i          (tp_int_i),
        .tp_rst_o          (tp_rst_o),
        .pres_sda_io       (pres_sda_io),
        .pres_scl_o        (pres_scl_o),
        .pump_o            (pump_o),
        .valve_v2_o        (valve_v2_o),
        .led_status_o      (led_status_o),
        .buzzer_o          (buzzer_o),
        .grip_req_i        (grip_req_i),
        .release_req_i     (release_req_i),
        .pressure_setpoint_i(pressure_setpoint_i),
        .pressure_kpa_o    (pressure_kpa_o),
        .fsm_state_o       (fsm_state_o),
        .safety_trigger_o  (safety_trigger_o),
        .touch_x_o         (touch_x_o),
        .touch_y_o         (touch_y_o),
        .touch_valid_o     (touch_valid_o)
    );

    i2c_slave_bfm #(.SLAVE_ADDR(7'h5D)) touch_slave (.scl(tp_scl_o), .sda(tp_sda_io));
    i2c_slave_bfm #(.SLAVE_ADDR(7'h6D)) pres_slave  (.scl(pres_scl_o), .sda(pres_sda_io));

    initial begin
        touch_slave.mem[0] = 8'h78;
        touch_slave.mem[1] = 8'h01;
        touch_slave.mem[2] = 8'h90;
        touch_slave.mem[3] = 8'h02;

        pres_slave.mem[0] = 8'h00;
        pres_slave.mem[1] = 8'h10;
        pres_slave.mem[2] = 8'h00;
    end

    initial begin
        $dumpfile("medical_glove_top.vcd");
        $dumpvars(0, tb_medical_glove_top);
    end

    initial sys_clk = 0;
    always #10 sys_clk = ~sys_clk;

    task print_status;
        begin
            case (fsm_state_o)
                3'd0: $write("IDLE");
                3'd1: $write("GRIP");
                3'd2: $write("HOLD");
                3'd3: $write("RELEASE");
                3'd4: $write("EMERGENCY");
                default: $write("UNKNOWN");
            endcase
            $display(" pump=%b v2=%b led=%b buzzer=%b safety=%b pressure=%d",
                     pump_o, valve_v2_o, led_status_o, buzzer_o, safety_trigger_o, pressure_kpa_o);
        end
    endtask

    initial begin
        $display("========================================");
        $display("  medical_glove_top Integration TB");
        $display("========================================");

        sys_rst_n = 1'b0;
        emerg_key_i = 1'b1;
        grip_req_i = 1'b0;
        release_req_i = 1'b0;
        pressure_setpoint_i = 16'd3000;
        tp_int_i = 1'b1;
        #200;
        sys_rst_n = 1'b1;
        #300;
        $display("[T=%0t] Reset done, system initialized", $time);

        wait(uut.rst_n_sync == 1'b1);
        $display("[T=%0t] rst_n_sync=1, system ready", $time);

        #1000;
        $display("[T=%0t] Initial state: ", $time);
        print_status;

        $display("[T=%0t] Pressing grip button...", $time);
        grip_req_i = 1'b1;
        #1000;
        grip_req_i = 1'b0;
        $display("[T=%0t] After grip_req: ", $time);
        print_status;

        #2000;
        $display("[T=%0t] Current state: ", $time);
        print_status;

        $display("[T=%0t] Pressing release button...", $time);
        release_req_i = 1'b1;
        #1000;
        release_req_i = 1'b0;
        $display("[T=%0t] After release_req: ", $time);
        print_status;

        $display("[T=%0t] Pressing emergency key...", $time);
        emerg_key_i = 1'b0;
        #2000;
        $display("[T=%0t] Emergency active: ", $time);
        print_status;

        emerg_key_i = 1'b1;
        #2000;
        $display("[T=%0t] Emergency released: ", $time);
        print_status;

        $display("[T=%0t] Touch coordinates: X=%d Y=%d valid=%b",
                 $time, touch_x_o, touch_y_o, touch_valid_o);

        $display("========================================");
        $display("  Test complete! Check VCD for waves.");
        $display("========================================");
        $finish;
    end

endmodule
