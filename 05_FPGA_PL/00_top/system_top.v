module system_top (
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    input  wire        sys_clk_i,
    input  wire        sys_rst_n_i,
    input  wire        emerg_key_i,

    output wire [23:0] lcd_rgb_o,
    output wire        lcd_hsync_o,
    output wire        lcd_vsync_o,
    output wire        lcd_de_o,
    output wire        lcd_pclk_o,
    output wire        lcd_bl_o,

    inout  wire        tp_scl_io,     /* EMIO[54] */
    inout  wire        tp_sda_io,     /* EMIO[55] */
    inout  wire        tp_rst_io,     /* EMIO[56] */
    inout  wire        tp_int_io,     /* EMIO[57] */

    inout  wire        pres_sda_io,
    output wire        pres_scl_o,

    output wire        pump_o,
    output wire        valve_v2_o,
    output wire        led_status_o,
    output wire        buzzer_o
);

    wire [63:0] emio_gpio_o;
    wire [63:0] emio_gpio_i;
    wire [63:0] emio_gpio_t;     /* 新增: GPIO_T 三态控制 */

    wire        grip_req     = emio_gpio_o[0];
    wire        release_req  = emio_gpio_o[1];
    wire [15:0] setpoint     = emio_gpio_o[17:2];

    wire [15:0] pressure_kpa;
    wire [2:0]  fsm_state;
    wire        safety_trigger;
    wire        sensor_fault;

    /* IOBUF 输出反馈 */
    wire        io_i_scl, io_i_sda, io_i_rst, io_i_int;

    /* 气泵控制 EMIO[19:0], 故障上报 EMIO[20], 其余未使用位接地 */
    assign emio_gpio_i[15:0]  = pressure_kpa;
    assign emio_gpio_i[18:16] = fsm_state;
    assign emio_gpio_i[19]    = safety_trigger;
    assign emio_gpio_i[20]    = sensor_fault;   /* 新增: 气压传感器通信故障 */
    assign emio_gpio_i[53:21] = 33'd0;
    assign emio_gpio_i[54]    = io_i_scl;
    assign emio_gpio_i[55]    = io_i_sda;
    assign emio_gpio_i[56]    = io_i_rst;
    assign emio_gpio_i[57]    = io_i_int;
    assign emio_gpio_i[63:58] = 6'd0;

    /* EMIO[54:57] IOBUF 三态缓冲器 */
    /* T=1: 输入模式(高阻), T=0: 输出模式(驱动I值) */
    IOBUF iobuf_scl (.I(emio_gpio_o[54]), .O(io_i_scl), .T(emio_gpio_t[54]), .IO(tp_scl_io));
    IOBUF iobuf_sda (.I(emio_gpio_o[55]), .O(io_i_sda), .T(emio_gpio_t[55]), .IO(tp_sda_io));
    IOBUF iobuf_rst (.I(emio_gpio_o[56]), .O(io_i_rst), .T(emio_gpio_t[56]), .IO(tp_rst_io));
    IOBUF iobuf_int (.I(emio_gpio_o[57]), .O(io_i_int), .T(emio_gpio_t[57]), .IO(tp_int_io));

    system_wrapper u_system_wrapper (
        .DDR_addr           (DDR_addr),
        .DDR_ba             (DDR_ba),
        .DDR_cas_n          (DDR_cas_n),
        .DDR_ck_n           (DDR_ck_n),
        .DDR_ck_p           (DDR_ck_p),
        .DDR_cke            (DDR_cke),
        .DDR_cs_n           (DDR_cs_n),
        .DDR_dm             (DDR_dm),
        .DDR_dq             (DDR_dq),
        .DDR_dqs_n          (DDR_dqs_n),
        .DDR_dqs_p          (DDR_dqs_p),
        .DDR_odt            (DDR_odt),
        .DDR_ras_n          (DDR_ras_n),
        .DDR_reset_n        (DDR_reset_n),
        .DDR_we_n           (DDR_we_n),
        .FIXED_IO_ddr_vrn   (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp   (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio       (FIXED_IO_mio),
        .FIXED_IO_ps_clk    (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb   (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb  (FIXED_IO_ps_srstb),

        .GPIO_O             (emio_gpio_o),
        .GPIO_I             (emio_gpio_i),
        .GPIO_T_0           (emio_gpio_t)     /* 新增: 三态控制 */
    );

    medical_glove_top u_glove_top (
        .sys_clk_i        (sys_clk_i),
        .sys_rst_n_i      (sys_rst_n_i),
        .emerg_key_i      (emerg_key_i),

        .lcd_rgb_o        (lcd_rgb_o),
        .lcd_hsync_o      (lcd_hsync_o),
        .lcd_vsync_o      (lcd_vsync_o),
        .lcd_de_o         (lcd_de_o),
        .lcd_pclk_o       (lcd_pclk_o),
        .lcd_bl_o         (lcd_bl_o),

        .pres_sda_io      (pres_sda_io),
        .pres_scl_o       (pres_scl_o),

        .pump_o           (pump_o),
        .valve_v2_o       (valve_v2_o),
        .led_status_o     (led_status_o),
        .buzzer_o         (buzzer_o),

        .grip_req_i       (grip_req),
        .release_req_i    (release_req),
        .setpoint_i       (setpoint),
        .pressure_kpa_o   (pressure_kpa),
        .fsm_state_o      (fsm_state),
        .safety_trigger_o (safety_trigger),
        .sensor_fault_o   (sensor_fault)
    );

endmodule
