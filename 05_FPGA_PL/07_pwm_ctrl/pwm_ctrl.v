`timescale 1ns / 1ps

module pwm_ctrl #(
    parameter WIDTH        = 8,
    parameter RAMP_CYC_PER_STEP = 32'd195_312   // 100MHz * 0.5s / 256 â‰? 195312
)(
    input  wire             clk_i,
    input  wire             rst_n_i,
    input  wire [WIDTH-1:0] duty_i,
    input  wire             enable_i,
    output reg              pwm_o
);

    reg [WIDTH-1:0] cnt;
    reg [WIDTH-1:0] duty_eff;
    reg [31:0]      ramp_cnt;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            duty_eff <= {WIDTH{1'b0}};
            ramp_cnt <= 32'd0;
        end else if (!enable_i) begin
            duty_eff <= {WIDTH{1'b0}};
            ramp_cnt <= 32'd0;
        end else if (duty_eff < duty_i) begin
            if (ramp_cnt >= RAMP_CYC_PER_STEP - 1) begin
                ramp_cnt <= 32'd0;
                duty_eff <= duty_eff + 1'b1;
            end else begin
                ramp_cnt <= ramp_cnt + 32'd1;
            end
        end else begin
            duty_eff <= duty_i;
            ramp_cnt <= 32'd0;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt   <= {WIDTH{1'b0}};
            pwm_o <= 1'b0;
        end else if (!enable_i) begin
            cnt   <= {WIDTH{1'b0}};
            pwm_o <= 1'b0;
        end else begin
            cnt   <= cnt + 1'b1;
            pwm_o <= (cnt < duty_eff) ? 1'b1 : 1'b0;
        end
    end

endmodule
