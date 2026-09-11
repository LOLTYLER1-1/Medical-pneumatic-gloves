`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// pressure_iic.v   Rev 2026-08-03
// 修订 1 (2026-08-02): 系数 12499->1250; 新增 sensor_fault_o 故障检测。
// 修订 2 (2026-08-03): 按 GZP6857D 官方规格书 V1.6 及其例程彻底重写读取流程,
//   修复台架实测"读数 0~90kPa 反复横跳"的四个根因:
//   a) 上电先读-改-写 Reg0xA5 (Raw_data_on=0 -> 输出校准数据)。旧代码从不配置,
//      若 OTP 默认 raw 模式, 读出的是未校准原始码 -> 大幅漂移/跳变;
//   b) 转换完成判定由"固定等 20ms"改为轮询 Reg0x30 的 sco 位(bit3), 2ms 一次,
//      300ms 超时记失败。旧代码在 OSR 偏高时会读到转换中的脏数据;
//   c) 3 个压力字节改为 3 次独立单字节读(官方例程方式), 不再假设寄存器
//      连续读自动递增(规格书未承诺);
//   d) 换算系数 1250 -> 1638。官方公式: ad/64 = Pa (100kPa 量程),
//      即 0.01kPa = ad/640 (raw*1638>>20 ≈ raw/640, 误差 0.01%)。
//      旧系数(按满量程 2^23=10000 假设)读数系统性偏小 24%。
//-----------------------------------------------------------------------------
module pressure_iic #(
    parameter CLK_FREQ_HZ = 32'd100_000_000,
    parameter SCL_FREQ_HZ = 32'd100_000,
    parameter SCL_DIV     = CLK_FREQ_HZ / (SCL_FREQ_HZ * 4),
    parameter SLAVE_ADDR  = 7'h6D,
    parameter POLL_MS     = 32'd50,                          /* 测量周期 50ms */
    parameter POLL_MAX    = (CLK_FREQ_HZ / 1000) * POLL_MS,
    parameter SCO_POLL_MAX= (CLK_FREQ_HZ / 1000) * 2,        /* sco 轮询间隔 2ms */
    parameter SCO_TIMEOUT = 8'd150                           /* sco 超时 150x2ms=300ms */
)(
    input  wire        clk_i,
    input  wire        rst_n_i,

    output reg         scl_o,
    inout  wire        sda_io,

    output reg  [15:0] pressure_kpa_o,   /* 气压, 单位 0.01kPa (10000 = 100.00 kPa) */
    output wire        sensor_fault_o    /* 1 = 传感器通信失败 (连续3次 NACK/卡低/超时) */
);

    /* SDA 开漏: oen=1 释放(上拉为高), oen=0 驱动 sda_out */
    reg        sda_oen;
    reg        sda_out;
    assign sda_io = sda_oen ? 1'bz : sda_out;
    wire sda_in = sda_io;

    /* 测量周期 kick: 每 POLL_MS 一个脉冲 */
    reg [31:0] poll_cnt;
    reg        kick_pulse;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            poll_cnt   <= 32'd0;
            kick_pulse <= 1'b0;
        end else if (poll_cnt >= POLL_MAX - 1) begin
            poll_cnt   <= 32'd0;
            kick_pulse <= 1'b1;
        end else begin
            poll_cnt   <= poll_cnt + 32'd1;
            kick_pulse <= 1'b0;
        end
    end

    /*======================= 字节泵 (一次完整 I2C 事务) =======================
     * 写事务: START -> {SLAVE,0} -> reg -> data -> STOP
     * 读事务: START -> {SLAVE,0} -> reg -> RSTART -> {SLAVE,1} -> 读1字节
     *         (主机 NACK) -> STOP        —— 与官方例程 Read/Write_One_Byte 一致
     * 握手: pump_start 脉冲启动, pump_done 脉冲结束; 期间任何 NACK 置 nack_flag
     *=======================================================================*/
    localparam P_IDLE   = 4'd0;
    localparam P_START  = 4'd1;
    localparam P_ADDR_W = 4'd2;
    localparam P_REG    = 4'd3;
    localparam P_WDATA  = 4'd4;
    localparam P_RSTART = 4'd5;
    localparam P_ADDR_R = 4'd6;
    localparam P_READ   = 4'd7;
    localparam P_STOP   = 4'd8;

    /*======================= 流程序列器 (官方例程步骤) =======================*/
    localparam SQ_IDLE     = 4'd0;   /* 等 kick_pulse; 首个周期先跑初始化 */
    localparam SQ_INIT_RD  = 4'd1;   /* 读 Reg0xA5 */
    localparam SQ_INIT_WR  = 4'd2;   /* 写回 0xA5 & 0xFD (Raw_data_on=0) */
    localparam SQ_CMD      = 4'd3;   /* 写 Reg0x30 = 0x0A (启动组合转换) */
    localparam SQ_SCO_WAIT = 4'd4;   /* sco 轮询间隔 2ms */
    localparam SQ_SCO_RD   = 4'd5;   /* 读 Reg0x30, 查 bit3(sco) */
    localparam SQ_RD_B0    = 4'd6;   /* 读 Reg0x06 (压力 MSB) */
    localparam SQ_RD_B1    = 4'd7;   /* 读 Reg0x07 (压力 CSB) */
    localparam SQ_RD_B2    = 4'd8;   /* 读 Reg0x08 (压力 LSB) */
    localparam SQ_CONVERT  = 4'd9;   /* 故障计数 + 乘法 */
    localparam SQ_CALC     = 4'd10;  /* 输出 */

    reg [3:0]  sstate, pstate;
    reg [1:0]  phase;
    reg [3:0]  bit_cnt;
    reg [15:0] scl_cnt;
    reg [31:0] wait_cnt;
    reg [7:0]  sco_cnt;
    reg [7:0]  tx_byte, rx_byte;
    reg        op_read;              /* 1=读事务, 0=写事务 */
    reg [7:0]  op_reg, op_wdata;
    reg        pump_start, pump_done;
    reg        init_done;            /* 0xA5 配置已完成 (整个上电期只做一次) */
    reg        nack_flag;            /* 本测量周期内出现过 NACK/卡低/sco超时 */
    reg [3:0]  err_cnt;
    reg        fault_r;
    reg [23:0] adc_raw;
    reg [39:0] calc_mul;
    reg        adc_neg;

    assign sensor_fault_o = fault_r;

    /* SCL 分频计数: 字节泵空闲时清零 */
    wire scl_tick = (scl_cnt == SCL_DIV - 1);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) scl_cnt <= 16'd0;
        else if (pstate == P_IDLE) scl_cnt <= 16'd0;
        else if (scl_tick) scl_cnt <= 16'd0;
        else scl_cnt <= scl_cnt + 16'd1;
    end

    /*======================== 主进程 (字节泵 + 序列器) ========================*/
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sstate         <= SQ_IDLE;
            pstate         <= P_IDLE;
            phase          <= 2'd0;
            bit_cnt        <= 4'd0;
            wait_cnt       <= 32'd0;
            sco_cnt        <= 8'd0;
            tx_byte        <= 8'd0;
            rx_byte        <= 8'd0;
            op_read        <= 1'b0;
            op_reg         <= 8'd0;
            op_wdata       <= 8'd0;
            pump_start     <= 1'b0;
            pump_done      <= 1'b0;
            init_done      <= 1'b0;
            nack_flag      <= 1'b0;
            err_cnt        <= 4'd0;
            fault_r        <= 1'b0;
            adc_raw        <= 24'd0;
            calc_mul       <= 40'd0;
            adc_neg        <= 1'b0;
            scl_o          <= 1'b1;
            sda_oen        <= 1'b1;
            sda_out        <= 1'b1;
            pressure_kpa_o <= 16'd0;
        end else begin
            pump_start <= 1'b0;      /* 默认: 仅单周期脉冲 */

            /*-------------------- 字节泵 --------------------*/
            case (pstate)
                P_IDLE: begin
                    scl_o <= 1'b1; sda_oen <= 1'b1; sda_out <= 1'b1;
                    phase <= 2'd0; pump_done <= 1'b0;
                    if (pump_start) pstate <= P_START;
                end

                /* I2C START: SCL 高时 SDA 拉低 */
                P_START: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; scl_o <= 1'b1; phase <= 2'd1; end
                            2'd1: begin sda_out <= 1'b0; phase <= 2'd2; end
                            2'd2: begin
                                scl_o <= 1'b0; phase <= 2'd0; bit_cnt <= 4'd0;
                                tx_byte <= {SLAVE_ADDR, 1'b0};
                                pstate  <= P_ADDR_W;
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                /* 发送一个字节 (地址/寄存器号/数据), 第 9 位收 ACK */
                P_ADDR_W, P_REG, P_WDATA, P_ADDR_R: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                sda_oen <= 1'b0;
                                if (bit_cnt < 4'd8) sda_out <= tx_byte[7 - bit_cnt];
                                else sda_oen <= 1'b1;          /* ACK 位释放总线 */
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                /* ACK 位 SCL 高期间 SDA 仍为高 = NACK */
                                if (bit_cnt == 4'd8 && sda_in) nack_flag <= 1'b1;
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1; phase <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0; phase <= 2'd0;
                                    case (pstate)
                                        P_ADDR_W: begin tx_byte <= op_reg; pstate <= P_REG; end
                                        P_REG   : begin
                                            if (op_read) pstate <= P_RSTART;
                                            else begin tx_byte <= op_wdata; pstate <= P_WDATA; end
                                        end
                                        P_WDATA : pstate <= P_STOP;
                                        P_ADDR_R: pstate <= P_READ;
                                        default : pstate <= P_IDLE;
                                    endcase
                                end
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                /* I2C Repeated START: SCL 低时先释放 SDA, 再拉高 SCL, 再拉低 SDA */
                P_RSTART: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; phase <= 2'd1; end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b0; phase <= 2'd3; end
                            2'd3: begin
                                scl_o <= 1'b0; phase <= 2'd0; bit_cnt <= 4'd0;
                                tx_byte <= {SLAVE_ADDR, 1'b1};
                                pstate  <= P_ADDR_R;
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                /* 接收一个字节, 第 9 位主机发 NACK 后结束 */
                P_READ: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                if (bit_cnt < 4'd8) sda_oen <= 1'b1;   /* 释放, 从机驱动 */
                                else begin sda_oen <= 1'b0; sda_out <= 1'b1; end  /* 主机 NACK */
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                if (bit_cnt < 4'd8) rx_byte <= {rx_byte[6:0], sda_in};
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1; phase <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0; phase <= 2'd0;
                                    pstate <= P_STOP;
                                end
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                /* I2C STOP: SCL 高时 SDA 低->高 */
                P_STOP: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b1; phase <= 2'd3; end
                            2'd3: begin phase <= 2'd0; pstate <= P_IDLE; pump_done <= 1'b1; end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                default: pstate <= P_IDLE;
            endcase

            /*-------------------- 流程序列器 --------------------*/
            case (sstate)
                SQ_IDLE: begin
                    if (kick_pulse) begin
                        /* 周期开始: 清 NACK 标志; 若总线被卡低(从机异常)直接记失败 */
                        nack_flag <= ~sda_in;
                        if (!init_done) begin
                            op_read <= 1'b1; op_reg <= 8'hA5;
                            pump_start <= 1'b1; sstate <= SQ_INIT_RD;
                        end else begin
                            op_read <= 1'b0; op_reg <= 8'h30; op_wdata <= 8'h0A;
                            pump_start <= 1'b1; sstate <= SQ_CMD;
                        end
                    end
                end

                /* 初始化: 读 0xA5 -> 清 bit1 -> 写回 (官方例程的 RMW) */
                SQ_INIT_RD: begin
                    if (pump_done) begin
                        op_read <= 1'b0; op_reg <= 8'hA5; op_wdata <= rx_byte & 8'hFD;
                        pump_start <= 1'b1; sstate <= SQ_INIT_WR;
                    end
                end
                SQ_INIT_WR: begin
                    if (pump_done) begin
                        init_done <= 1'b1;
                        sstate    <= SQ_CONVERT;      /* 初始化周期不做测量, 直接结账 */
                    end
                end

                /* 写 0x30=0x0A 启动组合转换, 然后进入 sco 轮询 */
                SQ_CMD: begin
                    if (pump_done) begin
                        sco_cnt  <= 8'd0;
                        wait_cnt <= 32'd0;
                        sstate   <= SQ_SCO_WAIT;
                    end
                end

                /* 每 2ms 查一次 sco, 最多 150 次 (300ms) */
                SQ_SCO_WAIT: begin
                    if (wait_cnt >= SCO_POLL_MAX - 1) begin
                        wait_cnt <= 32'd0;
                        if (sco_cnt >= SCO_TIMEOUT - 1) begin
                            nack_flag <= 1'b1;            /* sco 超时 = 本周期失败 */
                            sstate    <= SQ_CONVERT;
                        end else begin
                            sco_cnt    <= sco_cnt + 8'd1;
                            op_read    <= 1'b1; op_reg <= 8'h30;
                            pump_start <= 1'b1;
                            sstate     <= SQ_SCO_RD;
                        end
                    end else begin
                        wait_cnt <= wait_cnt + 32'd1;
                    end
                end
                SQ_SCO_RD: begin
                    if (pump_done) begin
                        if (!rx_byte[3]) begin            /* sco=0: 转换完成 */
                            op_read <= 1'b1; op_reg <= 8'h06;
                            pump_start <= 1'b1; sstate <= SQ_RD_B0;
                        end else begin
                            sstate <= SQ_SCO_WAIT;        /* 继续等 */
                        end
                    end
                end

                /* 3 次独立单字节读 (官方例程方式) */
                SQ_RD_B0: begin
                    if (pump_done) begin
                        adc_raw[23:16] <= rx_byte;
                        op_reg <= 8'h07; pump_start <= 1'b1; sstate <= SQ_RD_B1;
                    end
                end
                SQ_RD_B1: begin
                    if (pump_done) begin
                        adc_raw[15:8] <= rx_byte;
                        op_reg <= 8'h08; pump_start <= 1'b1; sstate <= SQ_RD_B2;
                    end
                end
                SQ_RD_B2: begin
                    if (pump_done) begin
                        adc_raw[7:0] <= rx_byte;
                        sstate <= SQ_CONVERT;
                    end
                end

                /* 故障计数 + 换算乘法 */
                SQ_CONVERT: begin
                    adc_neg  <= adc_raw[23];
                    /* 官方公式: 0.01kPa = ad/640 = ad*1638>>20 (误差 0.01%) */
                    calc_mul <= {1'b0, adc_raw[22:0]} * 40'd1638;
                    /* 连续 3 个周期失败 -> 故障; 任一周期成功即恢复 */
                    if (nack_flag) begin
                        if (err_cnt < 4'd15) err_cnt <= err_cnt + 4'd1;
                        if (err_cnt >= 4'd2) fault_r <= 1'b1;
                    end else begin
                        err_cnt <= 4'd0;
                        fault_r <= 1'b0;
                    end
                    sstate <= SQ_CALC;
                end

                SQ_CALC: begin
                    /* 负压(低于大气)或通信故障: 压力钳 0 */
                    if (adc_neg || fault_r) pressure_kpa_o <= 16'd0;
                    else                    pressure_kpa_o <= calc_mul[35:20];
                    sstate <= SQ_IDLE;
                end

                default: sstate <= SQ_IDLE;
            endcase
        end
    end

endmodule
