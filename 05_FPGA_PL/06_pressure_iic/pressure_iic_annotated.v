`timescale 1ns / 1ps

//=============================================================================
// File        : pressure_iic_annotated.v   ★教学版（不要加入工程综合）★
// 类比: Arduino 中读 BMP280 的简化版, IIC 主机自己写
//
// Rev 2026-08-03 按官方规格书 V1.6 及其例程彻底重写读取流程,
// 修台架实测"读数 0~90kPa 反复横跳"的四个根因:
//   a) 上电先读-改-写 Reg0xA5 (Raw_data_on=0 -> 输出校准数据)。旧代码从不配置,
//      若 OTP 默认 raw 模式, 读出的是未校准原始码 -> 大幅漂移/跳变;
//   b) 转换完成判定由"固定等 20ms"改为轮询 Reg0x30 的 sco 位(bit3), 2ms 一次,
//      300ms 超时记失败。旧代码在 OSR 偏高时会读到转换中的脏数据;
//   c) 3 个压力字节改为 3 次独立单字节读(官方例程方式), 不再假设寄存器
//      连续读自动递增(规格书未承诺);
//   d) 换算系数 1250 -> 1638。官方公式: ad/64 = Pa (100kPa 量程),
//      即 0.01kPa = ad/640 (raw*1638>>20 ≈ raw/640, 误差 0.01%)。
//
// ★ 保留 sensor_fault_o: 连续 3 个测量周期 NACK/总线卡低/sco超时 → 故障置位。
//   为什么必须做: 传感器掉线时 SDA 被上拉为高, 读数全 1, 若不检出,
//   FSM 永远等不到目标压力 → 气泵无限充气, 超压联锁也因读数失真而失效。
//   检出故障后由顶层进 EMERGENCY (泵停阀开泄气 + 蜂鸣)。
//
// 官方例程标准流程 (datasheet 附录 C 代码):
//   temp_a5 = Read(0xA5); Write(0xA5, temp_a5 & 0xFD);   // 校准输出模式
//   Write(0x30, 0x0A);                                    // 启动组合转换
//   while (Read(0x30) & 0x08);                            // 等 sco=0
//   ad = Read(0x06)*65536 + Read(0x07)*256 + Read(0x08);  // 24bit
//   if (ad > 8388608) pas = (ad-16777216)/64/1000;        // 负压(补码)
//   else              pas = ad/64/1000;                   // kPa
//=============================================================================
module pressure_iic #(
    parameter CLK_FREQ_HZ = 32'd100_000_000,    // 系统时钟 100MHz
    parameter SCL_FREQ_HZ = 32'd100_000,        // I2C SCL 100kHz
    parameter SCL_DIV     = CLK_FREQ_HZ / (SCL_FREQ_HZ * 4),  // 1/4 SCL 周期计数值
    parameter SLAVE_ADDR  = 7'h6D,              // 传感器 I2C 地址
    parameter POLL_MS     = 32'd50,             // 测量周期 50ms
    parameter POLL_MAX    = (CLK_FREQ_HZ / 1000) * POLL_MS,
    parameter SCO_POLL_MAX= (CLK_FREQ_HZ / 1000) * 2,   // sco 轮询间隔 2ms
    parameter SCO_TIMEOUT = 8'd150              // sco 超时 150x2ms=300ms
)(
    input  wire        clk_i,
    input  wire        rst_n_i,

    output reg         scl_o,                   // SCL 推挽输出
    inout  wire        sda_io,                  // SDA 开漏双向

    output reg  [15:0] pressure_kpa_o,          // 气压, 0.01kPa (10000=100.00kPa)
    output wire        sensor_fault_o           // 1 = 连续 3 周期通信失败
);

    // === SDA 开漏驱动: oen=1 释放(外部上拉为高), oen=0 驱动 sda_out ===
    reg        sda_oen;
    reg        sda_out;
    assign sda_io = sda_oen ? 1'bz : sda_out;   // 释放时为高阻, 上拉电阻拉高
    wire sda_in = sda_io;                       // 读回总线电平

    // === 测量周期 kick: 每 50ms 一个脉冲, 触发一次完整测量 ===
    reg [31:0] poll_cnt;
    reg        kick_pulse;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            poll_cnt   <= 32'd0;
            kick_pulse <= 1'b0;
        end else if (poll_cnt >= POLL_MAX - 1) begin
            poll_cnt   <= 32'd0;
            kick_pulse <= 1'b1;                 // 到点: 发一个周期脉冲
        end else begin
            poll_cnt   <= poll_cnt + 32'd1;
            kick_pulse <= 1'b0;
        end
    end

    // === 字节泵状态: 完成一次完整 I2C 事务 ===
    // 写事务: START -> {SLAVE,0} -> reg -> data -> STOP
    // 读事务: START -> {SLAVE,0} -> reg -> RSTART -> {SLAVE,1} -> 读1字节(NACK) -> STOP
    localparam P_IDLE   = 4'd0;                 // 空闲, 等 pump_start
    localparam P_START  = 4'd1;                 // START 条件
    localparam P_ADDR_W = 4'd2;                 // 发 {地址,W}
    localparam P_REG    = 4'd3;                 // 发寄存器号
    localparam P_WDATA  = 4'd4;                 // 发数据 (仅写事务)
    localparam P_RSTART = 4'd5;                 // 重复 START (仅读事务)
    localparam P_ADDR_R = 4'd6;                 // 发 {地址,R}
    localparam P_READ   = 4'd7;                 // 收 1 字节, 主机 NACK
    localparam P_STOP   = 4'd8;                 // STOP 条件, 发 pump_done

    // === 流程序列器状态: 按官方例程步骤组织一次测量 ===
    localparam SQ_IDLE     = 4'd0;              // 等 kick; 首周期先跑初始化
    localparam SQ_INIT_RD  = 4'd1;              // 读 Reg0xA5
    localparam SQ_INIT_WR  = 4'd2;              // 写回 0xA5&0xFD (关 raw 模式)
    localparam SQ_CMD      = 4'd3;              // 写 0x30=0x0A 启动组合转换
    localparam SQ_SCO_WAIT = 4'd4;              // sco 轮询间隔 2ms
    localparam SQ_SCO_RD   = 4'd5;              // 读 0x30 查 bit3
    localparam SQ_RD_B0    = 4'd6;              // 读 0x06 压力 MSB
    localparam SQ_RD_B1    = 4'd7;              // 读 0x07 压力 CSB
    localparam SQ_RD_B2    = 4'd8;              // 读 0x08 压力 LSB
    localparam SQ_CONVERT  = 4'd9;              // 故障计数 + 乘法
    localparam SQ_CALC     = 4'd10;             // 输出压力

    reg [3:0]  sstate, pstate;                  // 序列器/字节泵状态
    reg [1:0]  phase;                           // 字节内 4 相 (0:放数据 1:SCL高 2:采样/ACK 3:SCL低)
    reg [3:0]  bit_cnt;                         // 位计数 0~8 (8=ACK 位)
    reg [15:0] scl_cnt;                         // SCL 分频计数
    reg [31:0] wait_cnt;                        // sco 轮询间隔计数
    reg [7:0]  sco_cnt;                         // sco 轮询次数
    reg [7:0]  tx_byte, rx_byte;                // 发送/接收字节
    reg        op_read;                         // 1=读事务 0=写事务
    reg [7:0]  op_reg, op_wdata;                // 事务寄存器号/写数据
    reg        pump_start, pump_done;           // 字节泵启动/完成脉冲
    reg        init_done;                       // 0xA5 已配置 (上电只做一次)
    reg        nack_flag;                       // 本测量周期出现过 NACK/卡低/超时
    reg [3:0]  err_cnt;                         // 连续失败周期计数
    reg        fault_r;                         // 故障锁存
    reg [23:0] adc_raw;                         // 24bit 原始压力码
    reg [39:0] calc_mul;                        // 乘法位宽: 2^23*1638 < 2^34
    reg        adc_neg;                         // raw[23]=1 -> 负压

    assign sensor_fault_o = fault_r;

    // === SCL 分频: 字节泵空闲时清零, 工作时 0~SCL_DIV-1 循环 ===
    wire scl_tick = (scl_cnt == SCL_DIV - 1);   // 1/4 SCL 周期节拍
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) scl_cnt <= 16'd0;
        else if (pstate == P_IDLE) scl_cnt <= 16'd0;
        else if (scl_tick) scl_cnt <= 16'd0;
        else scl_cnt <= scl_cnt + 16'd1;
    end

    // === 主进程: 字节泵 + 序列器 (同一 always, 避免多驱动) ===
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
            pump_start <= 1'b0;                 // 默认: start 只发一个周期

            //---------------- 字节泵 ----------------
            case (pstate)
                P_IDLE: begin
                    scl_o <= 1'b1; sda_oen <= 1'b1; sda_out <= 1'b1;  // 总线释放
                    phase <= 2'd0; pump_done <= 1'b0;
                    if (pump_start) pstate <= P_START;    // 序列器发来事务
                end

                // START: SCL 高时 SDA 由高拉低
                P_START: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; scl_o <= 1'b1; phase <= 2'd1; end
                            2'd1: begin sda_out <= 1'b0; phase <= 2'd2; end   // SDA 下降沿=START
                            2'd2: begin
                                scl_o <= 1'b0; phase <= 2'd0; bit_cnt <= 4'd0;
                                tx_byte <= {SLAVE_ADDR, 1'b0};        // 装从机地址+W
                                pstate  <= P_ADDR_W;
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                // 发一个字节 (地址/寄存器/数据共用), 第 9 位读 ACK
                P_ADDR_W, P_REG, P_WDATA, P_ADDR_R: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                sda_oen <= 1'b0;
                                if (bit_cnt < 4'd8) sda_out <= tx_byte[7 - bit_cnt];  // MSB 先出
                                else sda_oen <= 1'b1;           // ACK 位释放总线给从机
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                if (bit_cnt == 4'd8 && sda_in) nack_flag <= 1'b1;  // SCL高时SDA高=NACK
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1; phase <= 2'd0;     // 下一位
                                end else begin
                                    bit_cnt <= 4'd0; phase <= 2'd0;
                                    case (pstate)                                 // 本字节发完, 决定下一状态
                                        P_ADDR_W: begin tx_byte <= op_reg; pstate <= P_REG; end
                                        P_REG   : begin
                                            if (op_read) pstate <= P_RSTART;      // 读事务 -> RSTART
                                            else begin tx_byte <= op_wdata; pstate <= P_WDATA; end
                                        end
                                        P_WDATA : pstate <= P_STOP;               // 写事务 -> STOP
                                        P_ADDR_R: pstate <= P_READ;               // 读事务 -> 收字节
                                        default : pstate <= P_IDLE;
                                    endcase
                                end
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                // Repeated START: SCL 低时先放 SDA 高, 抬 SCL, 再拉低 SDA
                P_RSTART: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b1; phase <= 2'd1; end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b0; phase <= 2'd3; end   // SCL高时SDA下降=RSTART
                            2'd3: begin
                                scl_o <= 1'b0; phase <= 2'd0; bit_cnt <= 4'd0;
                                tx_byte <= {SLAVE_ADDR, 1'b1};        // 装从机地址+R
                                pstate  <= P_ADDR_R;
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                // 收一个字节 (MSB 先进), 第 9 位主机发 NACK 表示只要 1 字节
                P_READ: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin
                                if (bit_cnt < 4'd8) sda_oen <= 1'b1;          // 释放, 从机驱动 SDA
                                else begin sda_oen <= 1'b0; sda_out <= 1'b1; end  // 主机 NACK
                                phase <= 2'd1;
                            end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                if (bit_cnt < 4'd8) rx_byte <= {rx_byte[6:0], sda_in};  // SCL高采样
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                if (bit_cnt < 4'd8) begin
                                    bit_cnt <= bit_cnt + 4'd1; phase <= 2'd0;
                                end else begin
                                    bit_cnt <= 4'd0; phase <= 2'd0;
                                    pstate <= P_STOP;                     // 收完 -> STOP
                                end
                            end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                // STOP: SCL 高时 SDA 由低放高
                P_STOP: begin
                    if (scl_tick) begin
                        case (phase)
                            2'd0: begin sda_oen <= 1'b0; sda_out <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl_o <= 1'b1; phase <= 2'd2; end
                            2'd2: begin sda_out <= 1'b1; phase <= 2'd3; end   // SDA 上升沿=STOP
                            2'd3: begin phase <= 2'd0; pstate <= P_IDLE; pump_done <= 1'b1; end
                            default: phase <= 2'd0;
                        endcase
                    end
                end

                default: pstate <= P_IDLE;
            endcase

            //---------------- 流程序列器 ----------------
            case (sstate)
                SQ_IDLE: begin
                    if (kick_pulse) begin
                        nack_flag <= ~sda_in;                 // 周期开始清标志; 总线卡低直接记失败
                        if (!init_done) begin                 // 首个周期: 先配置 0xA5
                            op_read <= 1'b1; op_reg <= 8'hA5;
                            pump_start <= 1'b1; sstate <= SQ_INIT_RD;
                        end else begin                        // 正常周期: 写转换命令
                            op_read <= 1'b0; op_reg <= 8'h30; op_wdata <= 8'h0A;
                            pump_start <= 1'b1; sstate <= SQ_CMD;
                        end
                    end
                end

                // 初始化: 读 0xA5, 清 bit1 (Raw_data_on=0 校准输出), 写回
                SQ_INIT_RD: begin
                    if (pump_done) begin
                        op_read <= 1'b0; op_reg <= 8'hA5; op_wdata <= rx_byte & 8'hFD;
                        pump_start <= 1'b1; sstate <= SQ_INIT_WR;
                    end
                end
                SQ_INIT_WR: begin
                    if (pump_done) begin
                        init_done <= 1'b1;
                        sstate    <= SQ_CONVERT;              // 初始化周期不测量, 直接结账
                    end
                end

                // 写完 0x0A, 进入 sco 轮询
                SQ_CMD: begin
                    if (pump_done) begin
                        sco_cnt  <= 8'd0;
                        wait_cnt <= 32'd0;
                        sstate   <= SQ_SCO_WAIT;
                    end
                end

                // 每 2ms 查一次 sco, 150 次 (300ms) 还没完成 = 超时失败
                SQ_SCO_WAIT: begin
                    if (wait_cnt >= SCO_POLL_MAX - 1) begin
                        wait_cnt <= 32'd0;
                        if (sco_cnt >= SCO_TIMEOUT - 1) begin
                            nack_flag <= 1'b1;
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
                        if (!rx_byte[3]) begin                // bit3=sco=0: 转换完成
                            op_read <= 1'b1; op_reg <= 8'h06;
                            pump_start <= 1'b1; sstate <= SQ_RD_B0;
                        end else begin
                            sstate <= SQ_SCO_WAIT;            // 还没好, 继续等
                        end
                    end
                end

                // 3 次独立单字节读 (官方例程方式, 不依赖自动递增)
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

                // 故障计数 + 官方公式乘法: 0.01kPa = ad/640 = ad*1638>>20
                SQ_CONVERT: begin
                    adc_neg  <= adc_raw[23];                  // bit23=1 为负压
                    calc_mul <= {1'b0, adc_raw[22:0]} * 40'd1638;
                    if (nack_flag) begin                      // 本周期失败
                        if (err_cnt < 4'd15) err_cnt <= err_cnt + 4'd1;
                        if (err_cnt >= 4'd2) fault_r <= 1'b1; // 连续 3 次 -> 故障
                    end else begin                            // 任一周期成功即恢复
                        err_cnt <= 4'd0;
                        fault_r <= 1'b0;
                    end
                    sstate <= SQ_CALC;
                end

                SQ_CALC: begin
                    if (adc_neg || fault_r) pressure_kpa_o <= 16'd0;  // 负压/故障钳 0
                    else                    pressure_kpa_o <= calc_mul[35:20];
                    sstate <= SQ_IDLE;
                end

                default: sstate <= SQ_IDLE;
            endcase
        end
    end

endmodule
