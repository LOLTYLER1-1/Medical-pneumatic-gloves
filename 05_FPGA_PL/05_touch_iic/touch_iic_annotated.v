//=============================================================================
// File        : touch_iic_annotated.v   ★教学版★
// 类比: Arduino 中 Wire.beginTransmission(0x5D); Wire.write(0x81); Wire.write(0x50);
//       Wire.endTransmission(false); Wire.requestFrom(0x5D,4);
//       这里全部用 RTL 状态机手撸 IIC 时序
//
// IIC 协议要点(Arduino Wire 库帮你做了, 这里要自己做):
//   START   : SCL=1 时 SDA 从 1→0
//   STOP    : SCL=1 时 SDA 从 0→1
//   传输1位 : SCL=0 时 SDA 变 → SCL=1 采样 → SCL=0 准备下一位
//   每 8 位后有 1 个 ACK 位 (主机让出 SDA, 从机拉低 = ACK)
//=============================================================================

`timescale 1ns / 1ps

module touch_iic #(
    parameter CLK_FREQ_HZ  = 32'd100_000_000,           // 主时钟 100 MHz
    parameter SCL_FREQ_HZ  = 32'd400_000,               // IIC SCL 频率 400 kHz
    parameter SCL_DIV      = CLK_FREQ_HZ / (SCL_FREQ_HZ * 4),  // 每个 1/4 SCL 周期 = 62 个主时钟
    parameter POLL_MS      = 32'd20,                    // 每 20ms 轮询一次触摸
    parameter POLL_MAX     = (CLK_FREQ_HZ / 1000) * POLL_MS,
    parameter SLAVE_ADDR   = 7'h5D                      // GT9147 IIC 地址(7 位)
)(
    input  wire        clk_i,                           // 100 MHz
    input  wire        rst_n_i,                         // 同步复位
    output reg         scl_o,                           // IIC 时钟线输出
    inout  wire        sda_io,                          // IIC 数据线(双向)
    input  wire        tp_int_i,                        // GT9147 中断线(有触摸=低)
    output reg         tp_rst_o,                        // GT9147 复位输出
    output reg  [11:0] touch_x_o,                       // 触摸坐标 X
    output reg  [11:0] touch_y_o,                       // 触摸坐标 Y
    output reg         touch_valid_o                    // 1=当前坐标有效
);

    // === SDA 双向控制三态门 ===
    reg sda_oen;                                        // 1=释放总线(高阻), 0=驱动 SDA
    reg sda_out;                                        // 主机要输出的电平
    assign sda_io = sda_oen ? 1'bz : sda_out;           // 三态控制
    wire sda_in = sda_io;                               // 输入采样(任何时候都可读)

    // === GT9147 上电复位序列: 拉低 RST 10ms, 拉高 10ms ===
    reg [31:0] rst_cnt;
    reg        rst_done;
    localparam RST_LOW_CYC = CLK_FREQ_HZ / 100;         // 10 ms
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rst_cnt  <= 32'd0;
            tp_rst_o <= 1'b0;                           // 上电默认拉低
            rst_done <= 1'b0;
        end else if (!rst_done) begin
            rst_cnt <= rst_cnt + 32'd1;
            if (rst_cnt < RST_LOW_CYC)
                tp_rst_o <= 1'b0;                       // 阶段 1: 低 10ms
            else if (rst_cnt < (RST_LOW_CYC * 2))
                tp_rst_o <= 1'b1;                       // 阶段 2: 高 10ms
            else
                rst_done <= 1'b1;                       // 复位完成
        end
    end

    // === 轮询定时器: 每 20ms 触发一次读取 ===
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
            start_pulse <= 1'b1;                        // 1 拍触发脉冲
        end else begin
            poll_cnt    <= poll_cnt + 32'd1;
            start_pulse <= 1'b0;
        end
    end

    // === 状态编码 ===
    localparam S_IDLE   = 5'd0;                         // 等待轮询触发
    localparam S_START  = 5'd1;                         // 发 START 条件
    localparam S_ADDR_W = 5'd2;                         // 写从机地址 W
    localparam S_REG_H  = 5'd3;                         // 写寄存器高字节 0x81
    localparam S_REG_L  = 5'd4;                         // 写寄存器低字节 0x50
    localparam S_RSTART = 5'd5;                         // 重新 START
    localparam S_ADDR_R = 5'd6;                         // 写从机地址 R
    localparam S_RD_XL  = 5'd7;                         // 读 X 低字节
    localparam S_RD_XH  = 5'd8;                         // 读 X 高字节
    localparam S_RD_YL  = 5'd9;                         // 读 Y 低字节
    localparam S_RD_YH  = 5'd10;                        // 读 Y 高字节(NACK)
    localparam S_STOP   = 5'd11;                        // STOP 条件
    localparam S_DONE   = 5'd12;                        // 数据更新

    reg [4:0]  state, next_state;
    reg [3:0]  bit_cnt;                                 // 0~8: 8 位数据 + 1 位 ACK
    reg [7:0]  tx_byte;                                 // 待发送字节
    reg [7:0]  rx_byte;                                 // 接收字节移位寄存器
    reg [1:0]  phase;                                   // 当前 SCL 子周期 (0~3, 对应 1/4 周期)
    reg [15:0] scl_cnt;                                 // SCL 子周期计数
    reg        ack_bit;                                 // 从机返回的 ACK

    reg [11:0] x_buf, y_buf;

    // === 1/4 SCL 周期 tick ===
    wire scl_tick = (scl_cnt == SCL_DIV - 1);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) scl_cnt <= 16'd0;
        else if (state == S_IDLE) scl_cnt <= 16'd0;
        else if (scl_tick) scl_cnt <= 16'd0;
        else scl_cnt <= scl_cnt + 16'd1;
    end

    // === 主状态机 ===
    // 每个数据位 phase 0~3 对应:
    //   0: SCL=0, SDA 变化(主发)
    //   1: SCL=1 上升
    //   2: SCL=1, 采样 SDA(收时)
    //   3: SCL=0 下降
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state         <= S_IDLE;
            phase         <= 2'd0;
            bit_cnt       <= 4'd0;
            scl_o         <= 1'b1;                      // 总线空闲: SCL/SDA 都拉高
            sda_oen       <= 1'b1;
            sda_out       <= 1'b1;
            tx_byte       <= 8'd0;
            rx_byte       <= 8'd0;
            ack_bit       <= 1'b0;
            x_buf         <= 12'd0;
            y_buf         <= 12'd0;
            touch_x_o     <= 12'd0;
            touch_y_o     <= 12'd0;
            touch_valid_o <= 1'b0;
        end else begin
            case (state)
                // ---- IDLE: 等待轮询触发 ----
                S_IDLE: begin
                    scl_o   <= 1'b1;
                    sda_oen <= 1'b1;
                    sda_out <= 1'b1;
                    phase   <= 2'd0;
                    if (start_pulse) begin
                        state   <= S_START;
                        tx_byte <= {SLAVE_ADDR, 1'b0};  // 7位地址 + W=0
                    end
                end

                // ---- START: SCL=1 时 SDA 从 1→0 ----
                S_START: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; scl_o <= 1'b1; phase <= 2'd1; end
                            2'd1: begin sda_out <= 1'b0; phase <= 2'd2; end  // 关键: SDA 下降
                            2'd2: begin scl_o <= 1'b0; phase <= 2'd0; state <= S_ADDR_W; bit_cnt <= 4'd0; end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                // ---- 写 1 字节: 8 位数据 + 1 位 ACK ----
                S_ADDR_W, S_REG_H, S_REG_L, S_ADDR_R: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin                  // SCL=0 时改变 SDA
                                sda_oen <= 1'b0;
                                if (bit_cnt < 4'd8)
                                    sda_out <= tx_byte[7 - bit_cnt];  // MSB 先发
                                else
                                    sda_oen <= 1'b1;     // ACK 位: 让出 SDA
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end       // SCL 拉高
                            2'd2: begin
                                if (bit_cnt == 4'd8) ack_bit <= sda_in;         // 采样 ACK
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_o <= 1'b0;                                  // SCL 拉低
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1;
                                    phase   <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0;
                                    phase   <= 2'd0;
                                    case (state)                                // 跳转下一字节
                                        S_ADDR_W: begin state <= S_REG_H; tx_byte <= 8'h81; end
                                        S_REG_H : begin state <= S_REG_L; tx_byte <= 8'h50; end
                                        S_REG_L : begin state <= S_RSTART; end
                                        S_ADDR_R: begin state <= S_RD_XL; end
                                        default : state <= S_IDLE;
                                    endcase
                                end
                            end
                        endcase
                    end
                end

                // ---- RESTART: 不发 STOP 直接再发一次 START (用于 写→读 切换) ----
                S_RSTART: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; phase <= 2'd1; end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b0; phase <= 2'd3; end
                            2'd3: begin scl_o <= 1'b0; phase <= 2'd0; state <= S_ADDR_R; tx_byte <= {SLAVE_ADDR, 1'b1}; bit_cnt <= 4'd0; end
                        endcase
                    end
                end

                // ---- 读 1 字节: 8 位数据 + 1 位 ACK/NACK ----
                S_RD_XL, S_RD_XH, S_RD_YL, S_RD_YH: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                if (bit_cnt < 4'd8) begin
                                    sda_oen <= 1'b1;                            // 读: 释放 SDA
                                end else begin
                                    sda_oen <= 1'b0;                            // 发 ACK/NACK
                                    sda_out <= (state == S_RD_YH) ? 1'b1 : 1'b0; // 最后一字节发 NACK
                                end
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                if (bit_cnt < 4'd8)
                                    rx_byte <= {rx_byte[6:0], sda_in};          // 左移收 MSB
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1;
                                    phase   <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0;
                                    phase   <= 2'd0;
                                    case (state)
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

                // ---- STOP: SCL=1 时 SDA 从 0→1 ----
                S_STOP: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b1; phase <= 2'd3; end     // 关键: SDA 上升
                            2'd3: begin phase <= 2'd0; state <= S_DONE; end
                        endcase
                    end
                end

                // ---- 数据更新 ----
                S_DONE: begin
                    touch_x_o     <= x_buf;
                    touch_y_o     <= y_buf;
                    touch_valid_o <= ~tp_int_i;          // INT 低 = 有触摸 = valid
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
