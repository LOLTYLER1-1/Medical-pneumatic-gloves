`timescale 1ns / 1ps

module i2c_slave_bfm #(
    parameter [6:0] SLAVE_ADDR = 7'h5D
)(
    input  wire scl,
    inout  wire sda
);

    reg sda_oe;
    reg sda_out;
    assign sda = sda_oe ? sda_out : 1'bz;

    reg start_detected;
    reg stop_detected;

    always @(negedge sda) if (scl === 1'b1) start_detected <= 1'b1;
    always @(posedge sda) if (scl === 1'b1) stop_detected  <= 1'b1;

    localparam S_IDLE   = 4'd0;
    localparam S_ADDR   = 4'd1;
    localparam S_ACK_A  = 4'd2;
    localparam S_WR     = 4'd3;
    localparam S_ACK_WR = 4'd4;
    localparam S_RD     = 4'd5;
    localparam S_ACK_RD = 4'd6;
    localparam S_WAIT   = 4'd7;

    reg [3:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] rx_shift;
    reg       rw;
    reg [7:0] mem [0:7];
    reg [2:0] rd_idx;

    integer j;
    initial begin
        state = S_IDLE;
        bit_cnt = 0;
        sda_oe = 0;
        sda_out = 1;
        start_detected = 0;
        stop_detected = 0;
        rd_idx = 0;
        for (j = 0; j < 8; j = j + 1) mem[j] = 8'h00;
    end

    always @(posedge scl) begin
        if (start_detected) begin
            start_detected = 0;
            state = S_ADDR;
            bit_cnt = 0;
            rx_shift = 0;
            sda_oe = 0;
        end else if (stop_detected) begin
            stop_detected = 0;
            state = S_IDLE;
            sda_oe = 0;
        end else begin
            case (state)
                S_ADDR: begin
                    rx_shift = {rx_shift[6:0], sda};
                    bit_cnt = bit_cnt + 1;
                    if (bit_cnt == 8) begin
                        rw = rx_shift[0];
                        state = S_ACK_A;
                        bit_cnt = 0;
                    end
                end
                S_ACK_A: begin
                    state = rw ? S_RD : S_WR;
                    if (rw) rd_idx = 0;
                end
                S_WR: begin
                    rx_shift = {rx_shift[6:0], sda};
                    bit_cnt = bit_cnt + 1;
                    if (bit_cnt == 8) begin
                        state = S_ACK_WR;
                        bit_cnt = 0;
                    end
                end
                S_ACK_WR: begin
                    state = S_WR;
                end
                S_RD: begin
                    bit_cnt = bit_cnt + 1;
                    if (bit_cnt == 8) begin
                        state = S_ACK_RD;
                        bit_cnt = 0;
                    end
                end
                S_ACK_RD: begin
                    if (sda === 1'b0) begin
                        rd_idx = rd_idx + 1;
                        state = S_RD;
                    end else begin
                        state = S_WAIT;
                    end
                end
                S_WAIT: begin
                end
            endcase
        end
    end

    always @(negedge scl) begin
        case (state)
            S_ACK_A:  begin sda_oe = 1; sda_out = 0; end
            S_ACK_WR: begin sda_oe = 1; sda_out = 0; end
            S_RD:     begin sda_oe = 1; sda_out = mem[rd_idx][7 - bit_cnt]; end
            S_ACK_RD: begin sda_oe = 0; end
            S_WR:     begin sda_oe = 0; end
            default:  begin sda_oe = 0; end
        endcase
    end

endmodule
