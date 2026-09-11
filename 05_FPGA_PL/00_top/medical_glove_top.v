`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// medical_glove_top.v   Rev 2026-08-03
// 修订 1 (2026-08-02): LCD 状态显示改回真实 fsm_state; 新增 sensor_fault_o 与
//         急停键同权处理; LCD 两个模块改用 33MHz 域同步复位 rst_n_sync_pclk。
// 修订 2 (2026-08-03): 新增 SIM_PRESSURE 参数 = 1: 压力源切换为 pressure_model
//         仿真模型 (真实传感器缺席/损坏时的演示模式), 同时屏蔽 sensor_fault
//         (否则传感器不在线会永久 EMERGENCY)。★ 开环估算, 严禁用于人体;
//         真实传感器到位后改回 0 即恢复闭环。
//-----------------------------------------------------------------------------
module medical_glove_top #(
    parameter SIM_PRESSURE = 1   /* 1=仿真压力模型(演示), 0=真实 XGZP6857D(闭环) */
)(
    input  wire        sys_clk_i,
    input  wire        sys_rst_n_i,
    input  wire        emerg_key_i,

    output wire [23:0] lcd_rgb_o,
    output wire        lcd_hsync_o,
    output wire        lcd_vsync_o,
    output wire        lcd_de_o,
    output wire        lcd_pclk_o,
    output wire        lcd_bl_o,

    inout  wire        pres_sda_io,
    output wire        pres_scl_o,

    output wire        pump_o,
    output wire        valve_v2_o,
    output wire        led_status_o,
    output wire        buzzer_o,

    input  wire        grip_req_i,
    input  wire        release_req_i,
    input  wire [15:0] setpoint_i,

    output wire [15:0] pressure_kpa_o,
    output wire [2:0]  fsm_state_o,
    output wire        safety_trigger_o,
    output wire        sensor_fault_o
);

    wire clk_100m;
    wire pclk_33m;
    wire rst_n_sync;
    wire rst_n_sync_pclk;

    wire        emerg_key_clean;
    wire        timing_hsync, timing_vsync, timing_de;
    wire [10:0] pixel_x;
    wire [10:0] pixel_y;
    wire [15:0] pressure_kpa;
    wire [2:0]  fsm_state;
    wire        pump_raw;
    wire        v2_raw;
    wire        pump_pwm;
    wire        safety_trigger;
    wire        sensor_fault;
    wire        emerg_any;
    wire        alarm_active;

    clock_reset u_clock_reset (
        .sys_clk_i        (sys_clk_i),
        .sys_rst_n_i      (sys_rst_n_i),
        .clk_100m_o       (clk_100m),
        .pclk_33m_o       (pclk_33m),
        .rst_n_sync_o     (rst_n_sync),
        .rst_n_sync_pclk_o(rst_n_sync_pclk)
    );

    key_debounce u_key_debounce (
        .clk_i       (clk_100m),
        .rst_n_i     (rst_n_sync),
        .key_raw_i   (emerg_key_i),
        .key_clean_o (emerg_key_clean)
    );

    lcd_timing u_lcd_timing (
        .pclk_i    (pclk_33m),
        .rst_n_i   (rst_n_sync_pclk),
        .hsync_o   (timing_hsync),
        .vsync_o   (timing_vsync),
        .de_o      (timing_de),
        .pixel_x_o (pixel_x),
        .pixel_y_o (pixel_y)
    );

    /* LCD 显示真实状态机状态 (2026-08-02 修正: 原为请求推导的调试用 display_state) */
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
    assign lcd_bl_o   = 1'b1;

    wire [15:0] pressure_sensor;   /* 真实传感器读数 */
    wire [15:0] pressure_sim;      /* 仿真模型推算值 */

    pressure_iic u_pressure_iic (
        .clk_i          (clk_100m),
        .rst_n_i        (rst_n_sync),
        .scl_o          (pres_scl_o),
        .sda_io         (pres_sda_io),
        .pressure_kpa_o (pressure_sensor),
        .sensor_fault_o (sensor_fault)
    );

    /* 仿真压力源: 跟随泵/阀实际输出推算理论压力 (演示模式) */
    pressure_model u_pressure_model (
        .clk_i      (clk_100m),
        .rst_n_i    (rst_n_sync),
        .pump_i     (pump_o),
        .valve_i    (valve_v2_o),
        .pressure_o (pressure_sim)
    );

    /* 压力源二选一 (SIM_PRESSURE 为常量, 综合时另一路自动优化掉) */
    assign pressure_kpa = (SIM_PRESSURE != 0) ? pressure_sim : pressure_sensor;

    /* 急停 = 按键急停 或 传感器故障 (仿真模式下屏蔽后者, 否则传感器
       不在线会永久 EMERGENCY) */
    assign emerg_any = (~emerg_key_clean) | (sensor_fault & (SIM_PRESSURE == 0));

    glove_fsm u_glove_fsm (
        .clk_i         (clk_100m),
        .rst_n_i       (rst_n_sync),
        .grip_req_i    (grip_req_i),
        .release_req_i (release_req_i),
        .emerg_i       (emerg_any),
        .pressure_i    (pressure_kpa),
        .setpoint_i    (setpoint_i),
        .state_o       (fsm_state),
        .pump_o        (pump_raw),
        .v2_o          (v2_raw)
    );

    pwm_ctrl u_pwm_ctrl (
        .clk_i    (clk_100m),
        .rst_n_i  (rst_n_sync),
        .duty_i   (8'd255),
        .enable_i (pump_raw),
        .pwm_o    (pump_pwm)
    );

    safety_interlock u_safety_interlock (
        .pressure_i (pressure_kpa),
        .pump_in_i  (pump_pwm),
        .v2_in_i    (v2_raw),
        .pump_out_o (pump_o),
        .v2_out_o   (valve_v2_o),
        .trigger_o  (safety_trigger)
    );

    /* 报警 = 超压联锁 或 急停(含传感器故障) */
    assign alarm_active = safety_trigger | emerg_any;

    buzzer_ctrl u_buzzer_ctrl (
        .clk_i     (clk_100m),
        .rst_n_i   (rst_n_sync),
        .trigger_i (alarm_active),
        .buzzer_o  (buzzer_o)
    );

    assign led_status_o     = (fsm_state != 3'd0);
    assign pressure_kpa_o   = pressure_kpa;
    assign fsm_state_o      = fsm_state;
    assign safety_trigger_o = safety_trigger;
    /* 仿真模式对 PS 也屏蔽故障上报, 避免误报 */
    assign sensor_fault_o   = (SIM_PRESSURE != 0) ? 1'b0 : sensor_fault;

endmodule
