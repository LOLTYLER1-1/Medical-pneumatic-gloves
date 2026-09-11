@echo off
chcp 65001 >nul
set SRC=..\00_top\medical_glove_top.v ..\01_clock_reset\clock_reset.v ..\02_key_debounce\key_debounce.v ..\03_lcd_timing\lcd_timing.v ..\04_lcd_display\lcd_display.v ..\05_touch_iic\touch_iic.v ..\06_pressure_iic\pressure_iic.v ..\07_pwm_ctrl\pwm_ctrl.v ..\08_glove_fsm\glove_fsm.v ..\09_safety_interlock\safety_interlock.v ..\10_axi_lite_reg\axi_lite_reg.v ..\11_buzzer\buzzer_ctrl.v

echo ========================================
echo  医用气动辅助手套 PL 端仿真脚本
echo ========================================
echo.

if "%1"=="safety" goto :safety
if "%1"=="axi" goto :axi
if "%1"=="buzzer" goto :buzzer
if "%1"=="fsm" goto :fsm
if "%1"=="pwm" goto :pwm
if "%1"=="key" goto :key
if "%1"=="lcd" goto :lcd
if "%1"=="clock" goto :clock
if "%1"=="display" goto :display
if "%1"=="touch" goto :touch
if "%1"=="pressure" goto :pressure
if "%1"=="top" goto :top

echo 用法: run_sim.bat [模块名]
echo.
echo 可用模块:
echo   safety    - safety_interlock
echo   axi       - axi_lite_reg
echo   buzzer    - buzzer_ctrl
echo   fsm       - glove_fsm
echo   pwm       - pwm_ctrl
echo   key       - key_debounce
echo   lcd       - lcd_timing
echo   clock     - clock_reset
echo   display   - lcd_display
echo   touch     - touch_iic
echo   pressure  - pressure_iic
echo   top       - medical_glove_top (集成测试)
goto :eof

:safety
iverilog -o safety.vvp ..\09_safety_interlock\safety_interlock.v tb_safety_interlock.v
vvp safety.vvp
goto :eof

:axi
iverilog -o axi.vvp ..\10_axi_lite_reg\axi_lite_reg.v tb_axi_lite_reg.v
vvp axi.vvp
goto :eof

:buzzer
iverilog -o buzzer.vvp ..\11_buzzer\buzzer_ctrl.v tb_buzzer_ctrl.v
vvp buzzer.vvp
goto :eof

:fsm
iverilog -o fsm.vvp ..\08_glove_fsm\glove_fsm.v tb_glove_fsm.v
vvp fsm.vvp
goto :eof

:pwm
iverilog -o pwm.vvp ..\07_pwm_ctrl\pwm_ctrl.v tb_pwm_ctrl.v
vvp pwm.vvp
goto :eof

:key
iverilog -o key.vvp ..\02_key_debounce\key_debounce.v tb_key_debounce.v
vvp key.vvp
goto :eof

:lcd
iverilog -o lcd.vvp ..\03_lcd_timing\lcd_timing.v tb_lcd_timing.v
vvp lcd.vvp
goto :eof

:clock
iverilog -o clock.vvp ..\01_clock_reset\clock_reset.v tb_clock_reset.v
vvp clock.vvp
goto :eof

:display
iverilog -o display.vvp ..\04_lcd_display\lcd_display.v tb_lcd_display.v
vvp display.vvp
goto :eof

:touch
iverilog -o touch.vvp ..\05_touch_iic\touch_iic.v i2c_slave_bfm.v tb_touch_iic.v
vvp touch.vvp
goto :eof

:pressure
iverilog -o pressure.vvp ..\06_pressure_iic\pressure_iic.v i2c_slave_bfm.v tb_pressure_iic.v
vvp pressure.vvp
goto :eof

:top
iverilog -o top.vvp %SRC% i2c_slave_bfm.v tb_medical_glove_top.v
vvp top.vvp
goto :eof
