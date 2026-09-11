`timescale 1ns / 1ps

module touch_iic #(
    parameter CLK_FREQ_HZ  = 32'd100_000_000,
    parameter SCL_FREQ_HZ  = 32'd50_000,
    parameter SCL_DIV      = CLK_FREQ_HZ / (SCL_FREQ_HZ * 4),
    parameter POLL_MS      = 32'd20,
    parameter POLL_MAX     = (CLK_FREQ_HZ / 1000) * POLL_MS,
    parameter SLAVE_ADDR   = 7'h5D
)(
    input  wire        clk_i,
    input  wire        rst_n_i,

    output wire        scl_o,
    inout  wire        sda_io,
    inout  wire        tp_int_io,
    output reg         tp_rst_o,

    output reg  [11:0] touch_x_o,
    output reg  [11:0] touch_y_o,
    output reg         touch_valid_o
);

    reg        sda_oen;
    reg        sda_out;
    assign sda_io = sda_oen ? 1'bz : sda_out;
    wire sda_in = sda_io;

    reg        scl_drv;
    assign scl_o = scl_drv ? 1'b0 : 1'bz;

    reg  int_oen;
    reg  int_out;
    wire int_in;
    assign tp_int_io = int_oen ? 1'bz : int_out;
    assign int_in   = tp_int_io;

    reg [31:0] rst_cnt;
    reg        rst_done;
    localparam PHASE1_END = CLK_FREQ_HZ / 100;          // 0-10ms: RST=0, INT=0 (host drives both)
    localparam PHASE2_END = PHASE1_END + CLK_FREQ_HZ/200; // 10-15ms: RST=1, INT=0 (hold INT low)
    localparam PHASE3_END = PHASE2_END + CLK_FREQ_HZ/2;   // 15-515ms: RST=1, INT released (boot)
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rst_cnt  <= 32'd0;
            tp_rst_o <= 1'b0;
            int_oen  <= 1'b0;
            int_out  <= 1'b0;
            rst_done <= 1'b0;
        end else if (!rst_done) begin
            rst_cnt <= rst_cnt + 32'd1;
            if (rst_cnt < PHASE1_END) begin
                tp_rst_o <= 1'b0; int_oen <= 1'b0; int_out <= 1'b0;
            end else if (rst_cnt < PHASE2_END) begin
                tp_rst_o <= 1'b1; int_oen <= 1'b0; int_out <= 1'b0;
            end else if (rst_cnt < PHASE3_END) begin
                tp_rst_o <= 1'b1; int_oen <= 1'b1;
            end else begin
                rst_done <= 1'b1;
            end
        end
    end

    reg [31:0] poll_cnt;
    reg        start_pulse;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            poll_cnt    <= 32'd0;
            start_pulse <= 1'b0;
        end else if (!rst_done) begin
            poll_cnt    <= 32'd0;
            start_pulse <= 1'b0;
        end else if (poll_cnt >= POLL_MAX - 1) begin
            poll_cnt    <= 32'd0;
            start_pulse <= 1'b1;
        end else begin
            poll_cnt    <= poll_cnt + 32'd1;
            start_pulse <= 1'b0;
        end
    end

    localparam S_IDLE      = 5'd0;
    localparam S_START     = 5'd1;
    localparam S_ADDR_W    = 5'd2;
    localparam S_REG_H     = 5'd3;
    localparam S_REG_L     = 5'd4;
    localparam S_RSTART    = 5'd5;
    localparam S_ADDR_R    = 5'd6;
    localparam S_RD_STATUS = 5'd7;
    localparam S_RD_RSV    = 5'd8;
    localparam S_RD_XL     = 5'd9;
    localparam S_RD_XH     = 5'd10;
    localparam S_RD_YL     = 5'd11;
    localparam S_RD_YH     = 5'd12;
    localparam S_STOP      = 5'd13;
    localparam S_DONE      = 5'd14;
    localparam S_CLR_DATA  = 5'd15;

    reg [4:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  tx_byte;
    reg [7:0]  rx_byte;
    reg [1:0]  phase;
    reg [15:0] scl_cnt;
    reg        ack_bit;
    reg        is_clear;
    reg        i2c_ack_ok;

    reg [11:0] x_buf;
    reg [11:0] y_buf;
    reg        touch_latch;

    wire scl_tick = (scl_cnt == SCL_DIV - 1);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) scl_cnt <= 16'd0;
        else if (state == S_IDLE) scl_cnt <= 16'd0;
        else if (scl_tick) scl_cnt <= 16'd0;
        else scl_cnt <= scl_cnt + 16'd1;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state    <= S_IDLE;
            phase    <= 2'd0;
            bit_cnt  <= 4'd0;
            scl_drv  <= 1'b0;
            sda_oen  <= 1'b1;
            sda_out  <= 1'b1;
            tx_byte  <= 8'd0;
            rx_byte  <= 8'd0;
            ack_bit    <= 1'b0;
            is_clear   <= 1'b0;
            i2c_ack_ok <= 1'b0;
            x_buf      <= 12'd0;
            y_buf    <= 12'd0;
            touch_x_o     <= 12'd0;
            touch_y_o     <= 12'd0;
            touch_valid_o <= 1'b0;
            touch_latch   <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    scl_drv <= 1'b0;
                    sda_oen <= 1'b1;
                    sda_out <= 1'b1;
                    phase   <= 2'd0;
                    if (start_pulse) begin
                        state    <= S_START;
                        tx_byte  <= {SLAVE_ADDR, 1'b0};
                        is_clear <= 1'b0;
                    end
                end

                S_START: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                if (!is_clear)
                                    touch_latch <= ~int_in;
                                sda_oen <= 1'b0; sda_out <= 1'b1; scl_drv <= 1'b0; phase <= 2'd1;
                            end
                            2'd1: begin sda_out <= 1'b0; phase <= 2'd2; end
                            2'd2: begin scl_drv <= 1'b1; phase <= 2'd0; state <= S_ADDR_W; bit_cnt <= 4'd0; end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                S_ADDR_W, S_REG_H, S_REG_L, S_CLR_DATA, S_ADDR_R: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                sda_oen <= 1'b0;
                                if (bit_cnt < 4'd8)
                                    sda_out <= tx_byte[7 - bit_cnt];
                                else
                                    sda_oen <= 1'b1;
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_drv <= 1'b0; phase <= 2'd2; end
                            2'd2: begin
                                if (bit_cnt == 4'd8) ack_bit <= sda_in;
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_drv <= 1'b1;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1;
                                    phase   <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0;
                                    phase   <= 2'd0;
                                    case (state)
                                        S_ADDR_W: begin
                                            i2c_ack_ok <= ~ack_bit;
                                            if (ack_bit) begin
                                                state <= S_STOP;
                                            end else begin
                                                state   <= S_REG_H;
                                                tx_byte <= 8'h81;
                                            end
                                        end
                                        S_REG_H: begin
                                            state   <= S_REG_L;
                                            tx_byte <= 8'h4E;
                                        end
                                        S_REG_L: begin
                                            if (is_clear) begin
                                                state   <= S_CLR_DATA;
                                                tx_byte <= 8'h00;
                                            end else begin
                                                state <= S_RSTART;
                                            end
                                        end
                                        S_CLR_DATA: begin
                                            state <= S_STOP;
                                        end
                                        S_ADDR_R: begin
                                            state <= S_RD_STATUS;
                                        end
                                        default: state <= S_IDLE;
                                    endcase
                                end
                            end
                        endcase
                    end
                end

                S_RSTART: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; phase <= 2'd1; end
                            2'd1: begin scl_drv <= 1'b0; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b0; phase <= 2'd3; end
                            2'd3: begin scl_drv <= 1'b1; phase <= 2'd0; state <= S_ADDR_R; tx_byte <= {SLAVE_ADDR, 1'b1}; bit_cnt <= 4'd0; end
                        endcase
                    end
                end

                S_RD_STATUS, S_RD_RSV, S_RD_XL, S_RD_XH, S_RD_YL, S_RD_YH: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                if (bit_cnt < 4'd8) begin
                                    sda_oen <= 1'b1;
                                end else begin
                                    sda_oen <= 1'b0;
                                    sda_out <= (state == S_RD_YH) ? 1'b1 : 1'b0;
                                end
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_drv <= 1'b0; phase <= 2'd2; end
                            2'd2: begin
                                if (bit_cnt < 4'd8)
                                    rx_byte <= {rx_byte[6:0], sda_in};
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_drv <= 1'b1;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1;
                                    phase   <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0;
                                    phase   <= 2'd0;
                                    case (state)
                                        S_RD_STATUS: state <= S_RD_RSV;
                                        S_RD_RSV:    state <= S_RD_XL;
                                        S_RD_XL: begin x_buf[7:0]  <= rx_byte; state <= S_RD_XH; end
                                        S_RD_XH: begin x_buf[11:8] <= rx_byte[3:0]; state <= S_RD_YL; end
                                        S_RD_YL: begin y_buf[7:0]  <= rx_byte; state <= S_RD_YH; end
                                        S_RD_YH: begin y_buf[11:8] <= rx_byte[3:0]; state <= S_STOP; end
                                        default: state <= S_STOP;
                                    endcase
                                end
                            end
                        endcase
                    end
                end

                S_STOP: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl_drv <= 1'b0; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b1; phase <= 2'd3; end
                            2'd3: begin
                                phase <= 2'd0;
                                if (is_clear)
                                    state <= S_IDLE;
                                else
                                    state <= S_DONE;
                            end
                        endcase
                    end
                end

                S_DONE: begin
                    touch_x_o     <= x_buf;
                    touch_y_o     <= y_buf;
                    touch_valid_o <= i2c_ack_ok;
                    is_clear <= 1'b1;
                    tx_byte  <= {SLAVE_ADDR, 1'b0};
                    state    <= S_START;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule