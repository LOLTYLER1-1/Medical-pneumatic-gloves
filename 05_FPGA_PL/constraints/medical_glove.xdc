#-----------------------------------------------------------------------------
# Medical Glove PL Constraints
# Version: 2026-08-02  增加显式主时钟约束 (原依赖 clk_wiz PRIM_IN_FREQ 自动衍生)
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# 1. 系统时钟 50MHz
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk_i]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk_i]

#-----------------------------------------------------------------------------
# 2. 复位键 KEY_RST
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n_i]

#-----------------------------------------------------------------------------
# 3. 急停按键 PL_KEY1
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33 PULLUP true} [get_ports emerg_key_i]

#-----------------------------------------------------------------------------
# 4. LCD RGB888 (ATK-MD0700R 7" 800x480)
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[0]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[1]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[3]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[4]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[5]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[6]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[7]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[8]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[9]}]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[10]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[11]}]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[12]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[13]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[14]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[15]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[16]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[17]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[18]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[19]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[20]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[21]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[22]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_o[23]}]

set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports lcd_hsync_o]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports lcd_vsync_o]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports lcd_de_o]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports lcd_bl_o]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports lcd_pclk_o]

#-----------------------------------------------------------------------------
# 5. 触摸 I2C (GT911) - 由 PS EMIO GPIO + 软件位bang I2C 驱动
#    SCL/SDA/RST/INT 均为 EMIO[54:57]，经 IOBUF 三态缓冲器连到物理引脚
#    PS 端通过 XGpioPs_SetOutputEnablePin() 控制方向（反映到 GPIO_T）
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports tp_scl_io]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33 PULLUP true} [get_ports tp_sda_io]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33}             [get_ports tp_rst_io]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports tp_int_io]

#-----------------------------------------------------------------------------
# 6. ATK MODULE 接口 (U4) - 气压 I2C + 气泵/阀门
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33 PULLUP true} [get_ports pres_scl_o]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33 PULLUP true} [get_ports pres_sda_io]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33}              [get_ports pump_o]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33}              [get_ports valve_v2_o]

#-----------------------------------------------------------------------------
# 7. 板载 LED0 - 状态指示
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports led_status_o]

#-----------------------------------------------------------------------------
# 7.1 板载蜂鸣器 M14
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports buzzer_o]

#-----------------------------------------------------------------------------
# 8. 异步输入信号 false_path
#-----------------------------------------------------------------------------
set_false_path -from [get_ports sys_rst_n_i]
set_false_path -from [get_ports emerg_key_i]
set_false_path -from [get_ports tp_int_io]

#-----------------------------------------------------------------------------
# 9. 跨时钟域 false_path
#    本设计有三个独立时钟源, 它们之间的数据交换都是异步的:
#      clk_out1_clk_wiz_0  = PL 100MHz (业务时钟, 跑 FSM/pressure_iic/buzzer)
#      clk_out2_clk_wiz_0  = LCD 33MHz (像素时钟, 跑 lcd_timing/lcd_display)
#      clk_fpga_0          = PS7 FCLK_CLK0 (AXI 总线驱动 AXI IIC/AXI GPIO)
#    EMIO GPIO[19:0] 信号在 clk_fpga_0 和 clk_out1_clk_wiz_0 之间穿越,
#    PL→PS 反馈信号也跨这两个域. 这些路径都是异步的, 免检.
#    注意: EMIO[54:57] 经 IOBUF 直连外部引脚, 不经过 PL 跨时钟域逻辑.
#
#    2026-08-03 修订: 时钟名改用通配符 "clk_out*_clk_wiz_0*".
#    原因: clk_wiz 按 OOC 综合后, 全工程链接时自动衍生的生成时钟与 IP 内部
#    XDC 里的时钟重名, Vivado 自动加 "_1" 后缀消歧, 实际布网后的名字是
#    "clk_out1_clk_wiz_0_1"/"clk_out2_clk_wiz_0_1". 精确名匹配落空,
#    get_clocks 返回空, 6 条 false_path 被静默丢弃 (综合日志仅 WARNING),
#    导致 100M->33M 的 13 条 LCD 显示跨域路径被误查, Setup WNS=-16.093ns.
#-----------------------------------------------------------------------------
set_false_path -from [get_clocks {clk_out1_clk_wiz_0*}] -to [get_clocks {clk_out2_clk_wiz_0*}]
set_false_path -from [get_clocks {clk_out2_clk_wiz_0*}] -to [get_clocks {clk_out1_clk_wiz_0*}]
set_false_path -from [get_clocks {clk_fpga_0*}]         -to [get_clocks {clk_out1_clk_wiz_0*}]
set_false_path -from [get_clocks {clk_out1_clk_wiz_0*}] -to [get_clocks {clk_fpga_0*}]
set_false_path -from [get_clocks {clk_fpga_0*}]         -to [get_clocks {clk_out2_clk_wiz_0*}]
set_false_path -from [get_clocks {clk_out2_clk_wiz_0*}] -to [get_clocks {clk_fpga_0*}]

#-----------------------------------------------------------------------------
# 10. Bitstream 配置
#-----------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
