`timescale 1ns / 1ps

//=============================================================================
// File        : medical_glove_top_annotated.v   ★教学版★
// Version     : 2026-08-02  (与 medical_glove_top.v 同步)
// 不要加入综合工程; 综合用 medical_glove_top.v
//=============================================================================
// 【架构】
//   PS (C 代码) → EMIO → grip_req/release_req/setpoint → PL FSM
//   PL → EMIO → pressure / fsm_state / safety / sensor_fault → PS
//   PL 自管: LCD 时序显示、气压 IIC、PWM、安全联锁、蜂鸣器、急停消抖
//
// 【Rev 2026-08-02 修订】
//   ★ LCD 显示改回真实 fsm_state (旧综合版曾用 grip/release 请求推导状态,
//     那是无传感器时期的调试残留, 教学版一直都是接真实状态, 现两版统一)
//   ★ 新增 sensor_fault 通路: 气压传感器通信失败时, 与急停键同权处理 —
//     emerg_any = 急停键 | 传感器故障 → FSM 进 EMERGENCY (泵停/阀开泄气)
//     同时蜂鸣器报警, 并经 sensor_fault_o → EMIO[20] 上报 PS
//   ★ LCD 两个模块改用 33MHz 域同步复位 rst_n_sync_pclk
//
// 【Rev 2026-08-03 修订】
//   ★ 新增 SIM_PRESSURE 参数 = 1: 压力源切换为 pressure_model 仿真模型
//     (真实传感器缺席/损坏时的演示模式), 同时屏蔽 sensor_fault
//     (否则传感器不在线会永久 EMERGENCY + 蜂鸣)。开环估算, 严禁用于人体;
//     真实传感器到位后改回 0 即恢复闭环。
//=============================================================================

module medical_glove_top #(
    parameter SIM_PRESSURE = 1   // 1=仿真压力模型(演示), 0=真实 XGZP6857D(闭环)
) (
    //-------------------------------------------------------------------------
    // 板级 IO（接到 XDC 引脚约束）
    //-------------------------------------------------------------------------
    input  wire        sys_clk_i,         // 50MHz 外部晶振（U18）
    input  wire        sys_rst_n_i,       // 复位键 KEY_RST（N16）
    input  wire        emerg_key_i,       // 急停按键 PL_KEY1（K16，低有效）

    // LCD RGB888（24 根数据 + 5 根控制）
    output wire [23:0] lcd_rgb_o,
    output wire        lcd_hsync_o,
    output wire        lcd_vsync_o,
    output wire        lcd_de_o,
    output wire        lcd_pclk_o,
    output wire        lcd_bl_o,          // 背光（常亮）

    // 气压传感器 I2C（这条总线 PL 自己跑，工作正常，保留）
    inout  wire        pres_sda_io,
    output wire        pres_scl_o,

    // 气泵 + 电磁阀 + LED + 蜂鸣器
    output wire        pump_o,            // 气泵 PWM
    output wire        valve_v2_o,        // 泄气阀（NO 常开，断电自动泄压）
    output wire        led_status_o,      // 状态 LED：非 IDLE 时亮
    output wire        buzzer_o,          // 蜂鸣器（板载 M14）

    //-------------------------------------------------------------------------
    // 与 PS 的接口（通过 system_top → BD wrapper → EMIO GPIO 来回传）
    //-------------------------------------------------------------------------
    // PS → PL（PS 算好按钮逻辑，把"现在要干嘛"告诉 PL）
    input  wire        grip_req_i,        // 1=请求抓握
    input  wire        release_req_i,     // 1=请求松手
    input  wire [15:0] setpoint_i,        // 压力目标值, 单位 0.01kPa

    // PL → PS（PS 读这几根线看仪表板）
    output wire [15:0] pressure_kpa_o,    // 实时气压, 单位 0.01kPa
    output wire [2:0]  fsm_state_o,       // 状态机当前状态
    output wire        safety_trigger_o,  // 是否在安全联锁状态（超压）
    output wire        sensor_fault_o     // 气压传感器通信失败 (2026-08-02 新增)
);

    //=========================================================================
    // 内部线网
    //=========================================================================
    wire clk_100m;          // PL 主时钟（处理业务、跑状态机）
    wire pclk_33m;          // LCD 像素时钟
    wire rst_n_sync;        // 100MHz 域同步复位
    wire rst_n_sync_pclk;   // 33MHz 域同步复位 (2026-08-02 新增)

    wire        emerg_key_clean;
    wire        timing_hsync, timing_vsync, timing_de;
    wire [10:0] pixel_x, pixel_y;
    wire [15:0] pressure_kpa;
    wire [2:0]  fsm_state;
    wire        pump_raw;            // FSM 的原始气泵指令
    wire        v2_raw;              // FSM 的原始阀门指令
    wire        pump_pwm;            // PWM 后的气泵指令
    wire        safety_trigger;
    wire        sensor_fault;        // 传感器通信故障 (来自 pressure_iic)
    wire        emerg_any;           // 急停键 | 传感器故障
    wire        alarm_active;

    //=========================================================================
    // 时钟和复位（MMCM 把 50MHz 倍频到 100MHz、分频到 33MHz）
    //=========================================================================
    clock_reset u_clock_reset (
        .sys_clk_i        (sys_clk_i),
        .sys_rst_n_i      (sys_rst_n_i),
        .clk_100m_o       (clk_100m),
        .pclk_33m_o       (pclk_33m),
        .rst_n_sync_o     (rst_n_sync),
        .rst_n_sync_pclk_o(rst_n_sync_pclk)   // 新增: 33M 域专用复位
    );

    //=========================================================================
    // 急停按键消抖：连续 N 次稳定才认为按下
    //=========================================================================
    key_debounce u_key_debounce (
        .clk_i       (clk_100m),
        .rst_n_i     (rst_n_sync),
        .key_raw_i   (emerg_key_i),
        .key_clean_o (emerg_key_clean)
    );

    //=========================================================================
    // LCD 时序生成（计数器扫像素位置） + 显示画面（仪表板）
    // 注意: 这两个模块在 33MHz 域, 复位用 rst_n_sync_pclk (2026-08-02 修正)
    //=========================================================================
    lcd_timing u_lcd_timing (
        .pclk_i    (pclk_33m),
        .rst_n_i   (rst_n_sync_pclk),
        .hsync_o   (timing_hsync),
        .vsync_o   (timing_vsync),
        .de_o      (timing_de),
        .pixel_x_o (pixel_x),
        .pixel_y_o (pixel_y)
    );

    // fsm_state_i 接真实状态机状态 (2026-08-02 起与教学版一致)
    lcd_display u_lcd_display (
        .pclk_i         (pclk_33m),
        .rst_n_i        (rst_n_sync_pclk),
        .hsync_i        (timing_hsync),
        .vsync_i        (timing_vsync),
        .de_i           (timing_de),
        .pixel_x_i      (pixel_x),
        .pixel_y_i      (pixel_y),
        .pressure_kpa_i (pressure_kpa),
        .fsm_state_i    (fsm_state),
        .hsync_o        (lcd_hsync_o),
        .vsync_o        (lcd_vsync_o),
        .de_o           (lcd_de_o),
        .rgb_o          (lcd_rgb_o)
    );

    assign lcd_pclk_o = pclk_33m;
    assign lcd_bl_o   = 1'b1;            // 背光常亮

    //=========================================================================
    // 气压传感器 I2C（XGZP6857D，自写软 I2C）
    // 2026-08-02: 新增 sensor_fault_o 输出 (连续 3 次 NACK/总线卡低 → 1)
    //=========================================================================
    wire [15:0] pressure_sensor;   // 真实传感器读数
    wire [15:0] pressure_sim;      // 仿真模型推算值

    pressure_iic u_pressure_iic (
        .clk_i          (clk_100m),
        .rst_n_i        (rst_n_sync),
        .scl_o          (pres_scl_o),
        .sda_io         (pres_sda_io),
        .pressure_kpa_o (pressure_sensor),
        .sensor_fault_o (sensor_fault)
    );

    //=========================================================================
    // 仿真压力源 (2026-08-03 新增): 跟随泵/阀实际输出推算理论压力
    // 阀开→快速泄气; 阀闭+泵开→充气; 阀闭+泵停→缓慢泄漏
    //=========================================================================
    pressure_model u_pressure_model (
        .clk_i      (clk_100m),
        .rst_n_i    (rst_n_sync),
        .pump_i     (pump_o),
        .valve_i    (valve_v2_o),
        .pressure_o (pressure_sim)
    );

    // 压力源二选一 (SIM_PRESSURE 为常量, 综合时另一路自动优化掉)
    assign pressure_kpa = (SIM_PRESSURE != 0) ? pressure_sim : pressure_sensor;

    //=========================================================================
    // 急停合并: 按键急停 或 传感器故障, 同权处理 (2026-08-02 新增)
    // 为什么要管传感器故障: 传感器掉线时压力读数恒 0, FSM 会以为永远没充够,
    // 气泵无限充气且超压联锁(靠压力读数)也失效 —— 必须按急停处理
    //=========================================================================
    // 仿真模式下屏蔽传感器故障 (传感器不在线不应永久 EMERGENCY)
    assign emerg_any = (~emerg_key_clean) | (sensor_fault & (SIM_PRESSURE == 0));

    //=========================================================================
    // 核心状态机：IDLE → GRIP → HOLD → RELEASE / EMERGENCY
    //=========================================================================
    glove_fsm u_glove_fsm (
        .clk_i         (clk_100m),
        .rst_n_i       (rst_n_sync),
        .grip_req_i    (grip_req_i),
        .release_req_i (release_req_i),
        .emerg_i       (emerg_any),          // 按键低有效取反后, 再或上传感器故障
        .pressure_i    (pressure_kpa),
        .setpoint_i    (setpoint_i),
        .state_o       (fsm_state),
        .pump_o        (pump_raw),
        .v2_o          (v2_raw)
    );

    //=========================================================================
    // 气泵 PWM 调制（占空比留接口，先用 100% 即全开; 模块内含 0.5s 软启动斜坡）
    //=========================================================================
    pwm_ctrl u_pwm_ctrl (
        .clk_i    (clk_100m),
        .rst_n_i  (rst_n_sync),
        .duty_i   (8'd255),
        .enable_i (pump_raw),
        .pwm_o    (pump_pwm)
    );

    //=========================================================================
    // 安全联锁：超压(80kPa)时强制停泵+开泄气阀（硬件级保护，软件错了也不出事）
    //=========================================================================
    safety_interlock u_safety_interlock (
        .pressure_i (pressure_kpa),
        .pump_in_i  (pump_pwm),
        .v2_in_i    (v2_raw),
        .pump_out_o (pump_o),
        .v2_out_o   (valve_v2_o),
        .trigger_o  (safety_trigger)
    );

    //=========================================================================
    // 报警 = 超压联锁触发 OR 急停(含传感器故障)  (2026-08-02 修订)
    //=========================================================================
    assign alarm_active = safety_trigger | emerg_any;

    buzzer_ctrl u_buzzer_ctrl (
        .clk_i     (clk_100m),
        .rst_n_i   (rst_n_sync),
        .trigger_i (alarm_active),
        .buzzer_o  (buzzer_o)
    );

    //=========================================================================
    // 状态 LED：非 IDLE 时亮
    //=========================================================================
    assign led_status_o = (fsm_state != 3'd0);

    //=========================================================================
    // 反馈信号引出到 system_top → BD wrapper → EMIO GPIO_I → PS
    //=========================================================================
    assign pressure_kpa_o   = pressure_kpa;
    assign fsm_state_o      = fsm_state;
    assign safety_trigger_o = safety_trigger;
    assign sensor_fault_o   = (SIM_PRESSURE != 0) ? 1'b0 : sensor_fault;  // 仿真模式屏蔽

endmodule
