# PL 端仿真文件说明

## 文件清单

| 序号 | Testbench | 被测模块 | 说明 |
|---|---|---|---|
| 1 | `tb_safety_interlock.v` | safety_interlock | 纯组合逻辑，测试压力阈值触发 |
| 2 | `tb_axi_lite_reg.v` | axi_lite_reg | 打拍寄存器，测试 EMIO 旁路 |
| 3 | `tb_buzzer_ctrl.v` | buzzer_ctrl | 2Hz 蜂鸣器，仿真时提速到 1kHz |
| 4 | `tb_glove_fsm.v` | glove_fsm | 5 态状态机，测试各状态转换 |
| 5 | `tb_pwm_ctrl.v` | pwm_ctrl | PWM + 软启动，仿真时缩短 ramp 时间 |
| 6 | `tb_key_debounce.v` | key_debounce | 按键消抖，仿真时缩到 1ms |
| 7 | `tb_lcd_timing.v` | lcd_timing | LCD 时序，用小参数快速验证一帧 |
| 8 | `tb_clock_reset.v` | clock_reset | 时钟+复位，用 mock 替代 clk_wiz_0 IP |
| 9 | `tb_lcd_display.v` | lcd_display | LCD 渲染，用 mock 替代 BROM IP |
| 10 | `tb_touch_iic.v` | touch_iic | 触摸 IIC，配合 i2c_slave_bfm |
| 11 | `tb_pressure_iic.v` | pressure_iic | 气压 IIC，配合 i2c_slave_bfm |
| 12 | `tb_medical_glove_top.v` | medical_glove_top | 顶层集成测试，含所有 mock |
| - | `i2c_slave_bfm.v` | (辅助模块) | IIC 从设备行为模型，供 10/11/12 使用 |

## Vivado 仿真步骤

1. 打开 Vivado 工程
2. **Add Sources** -> **Add Simulation Sources**
3. 选择 `sim/` 目录下的 `.v` 文件（根据要测的模块选择对应的 tb）
4. 在 **Simulation Sources** 中右键对应 testbench -> **Set as Top**
5. 点击 **Run Simulation** -> **Run Behavioral Simulation**
6. 在波形窗口中添加需要观察的信号，运行仿真

## iverilog + GTKWave (免费方案)

如果安装了 iverilog 和 GTKWave，可以用以下命令行编译运行：

```bash
# 进入 sim 目录
cd "D:\medical project\05_FPGA_PL端\sim"

# 例：编译并运行 safety_interlock 的 testbench
iverilog -o safety_interlock.vvp ../09_safety_interlock/safety_interlock.v tb_safety_interlock.v
vvp safety_interlock.vvp
gtkwave safety_interlock.vcd

# 例：运行 clock_reset（需要 mock clk_wiz_0）
iverilog -o clock_reset.vvp ../01_clock_reset/clock_reset.v tb_clock_reset.v
vvp clock_reset.vvp

# 例：运行 top 级集成测试（需要所有子模块 + mocks）
iverilog -o top.vvp \
  ../00_top/medical_glove_top.v \
  ../01_clock_reset/clock_reset.v \
  ../02_key_debounce/key_debounce.v \
  ../03_lcd_timing/lcd_timing.v \
  ../04_lcd_display/lcd_display.v \
  ../05_touch_iic/touch_iic.v \
  ../06_pressure_iic/pressure_iic.v \
  ../07_pwm_ctrl/pwm_ctrl.v \
  ../08_glove_fsm/glove_fsm.v \
  ../09_safety_interlock/safety_interlock.v \
  ../10_axi_lite_reg/axi_lite_reg.v \
  ../11_buzzer/buzzer_ctrl.v \
  i2c_slave_bfm.v tb_medical_glove_top.v
vvp top.vvp
```

## 文件命名约定

- `tb_xxx.v` = 干净版 testbench（无注释，直接用于仿真）
- `tb_xxx_annotated.v` = 教学版（每行注释，学习用，**不加入 Vivado 工程**）
