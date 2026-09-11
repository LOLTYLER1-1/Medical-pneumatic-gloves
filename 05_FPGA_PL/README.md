# 05_FPGA_PL端 - Verilog 工程

> 医用气动辅助手套 - ZYNQ7020 PL 端
> 工具链: Vivado 2020.2
> 顶层模块: **`00_top/medical_glove_top.v`** ★

---

## 一、文件结构

```
05_FPGA_PL/
├── README.md                                  本文件
├── 00_top/
│   ├── medical_glove_top.v                    顶层 (综合用, 含 SIM_PRESSURE 参数)
│   ├── medical_glove_top_annotated.v          顶层 (教学版)
│   └── system_top.v                           连接 BD wrapper + glove 顶层的包装
├── 01_clock_reset/                            时钟/复位 (依赖 clk_wiz_0)
├── 02_key_debounce/                           按键消抖
├── 03_lcd_timing/                             LCD 行场时序
├── 04_lcd_display/                            UI 渲染 (含压力数值 BCD 字库)
├── 05_touch_iic/                              触摸 IIC 主机 (★ 早期方案, 最终触摸走 PS EMIO)
├── 06_pressure_iic/                           XGZP6857D 气压 IIC 主机 (官方规格书重写版)
├── 07_pwm_ctrl/                               气泵软启动 PWM
├── 08_glove_fsm/                              主状态机
├── 09_safety_interlock/                       硬件安全联锁 (纯组合)
├── 10_axi_lite_reg/                           EMIO 旁路寄存器
├── 11_buzzer/                                 蜂鸣器 2Hz 告警 (板载 M14)
├── 12_pressure_model/                         仿真压力模型 (SIM_PRESSURE=1 时顶替传感器)
├── ip_sources/lcd_image.coe                   屏幕中心图片初始化文件 (200x175 RGB565)
├── constraints/medical_glove.xdc              引脚约束
├── sim/                                       Testbench + Python 仿真验证脚本
├── vivado_bd_emio_fix.tcl                     BD EMIO 修复脚本
└── 用户操作清单.docx                           Vivado 操作步骤记录
```

每个子目录里:
- `xxx.v`           = 干净版 (加入 Vivado 工程综合)
- `xxx_annotated.v` = 教学版 (每行注释, **不要加入工程**)

---

## 二、需要在 Vivado 中创建的 IP 核

需要 **2 个 IP** + **PS7 (Block Design 添加)**:

### IP 1: Clocking Wizard `clk_wiz_0`

**作用**: 50 MHz → 100 MHz + 33.33 MHz

**创建步骤**:
1. Vivado → `IP Catalog` → 搜索 `Clocking Wizard` → 双击
2. 在 `Clocking Options` 选项卡:
   - Primary: `Single ended clock capable pin`
   - Source frequency: `50.000` MHz
3. 在 `Output Clocks` 选项卡:
   - `clk_out1` 勾选, 频率填 `100.000`
   - `clk_out2` 勾选, 频率填 `33.333`
   - `reset type` 选 `Active Low` (与 RTL 中的 `resetn` 端口匹配)
   - 勾选 `locked` 输出
4. Component Name 保持默认 `clk_wiz_0` → OK → Generate

### IP 2: Block Memory Generator `lcd_image_rom` (屏幕中心图片)

**作用**: 存放 200x175 RGB565 图片, 给 `lcd_display.v` 模块读取

**创建步骤**:
1. Vivado → `IP Catalog` → 搜索 `Block Memory Generator` → 双击
2. `Component Name` 必须填 **`lcd_image_rom`** (与 lcd_display.v 例化名一致)
3. `Basic` 选项卡:
   - Interface Type: `Native`
   - Memory Type: **`Single Port ROM`**
4. `Port A Options` 选项卡:
   - Port A Width: **`16`**  (RGB565)
   - Port A Depth: **`35000`** (= 200 × 175)
   - Enable Port Type: `Always Enabled`
   - **取消勾选** `Primitive Output Register` (减少 1 拍延迟; 不取消则需要再加 1 级 pipeline)
   - 实际默认 1 拍延迟即可, RTL 代码已按 1 拍延迟对齐
5. `Other Options` 选项卡:
   - **勾选** `Load Init File`
   - Coe File: 点 `Browse` 选 `<工程目录>/ip_sources/lcd_image.coe`
   - 等校验通过 (会显示像素数 = 35000)
6. → OK → Generate Output Products

**图片位置**:
- 屏幕中心 (300, 152) → (499, 326)
- 屏幕 800×480 减图片 200×175 居中

**RGB565 → RGB888**: 由 RTL 自动做位扩展, 不需关心

### Block Design 中: ZYNQ7 Processing System (PS7)

PS7 不是"创建", 是在 Block Design 里拖一个 IP 进去:

1. `Create Block Design` → 名字 `system`
2. 右键空白 → `Add IP` → 选 `ZYNQ7 Processing System`
3. 双击 PS7 IP 弹出配置:
   - **MIO Configuration**:
     - 关掉所有用不到的(例如 USB/Ethernet/SDIO 按板子实际可用情况)
     - 保留 UART1 (Vitis 串口打印用)
   - **PS-PL Configuration → General → Enable Clock Resets → FCLK_RESET0_N**: 勾选
   - **PS-PL Configuration → AXI Non Secure Enablement → GP Master AXI**: 勾选 M_AXI_GP0
   - **MIO Configuration → I/O Peripherals → GPIO → EMIO GPIO Width**: 填 `64`
     (最终映射: 输出 EMIO[0]=grip_req, [1]=release_req, [17:2]=setpoint(0.01kPa);
      输入 EMIO[15:0]=压力, [18:16]=FSM状态, [19]=safety_trigger, [20]=sensor_fault;
      触摸 IIC 走 EMIO[54:57] = XGpioPs pin 108~111)
   - **Clock Configuration → PL Fabric Clocks → FCLK_CLK0**: 50 MHz (与 PL 系统时钟一致, 但实际我们用板上有源晶振, 这里 FCLK_CLK0 可以不接, 留默认)
4. 点 `Run Block Automation` → 自动连复位

### (可选) Integrated Logic Analyzer `ila_0` - 调试用

仅在仿真后还需在板上抓信号时添加。本工程不强制依赖。

---

## 三、Vivado 工程创建完整步骤

### 1) 新建工程
- File → New Project → Project Type: `RTL Project`
- Default Part: `xc7z020clg400-2`

### 2) 添加源文件 (只添加干净版, 不要添加 `_annotated.v`)
- `Add Sources` → `Add or create design sources`
- 选 13 个子目录里的干净版 .v 文件 (顶层 + system_top + 12 个子模块)
- 添加约束: `constraints/medical_glove.xdc`

### 3) 添加 IP
- `IP Catalog` → Clocking Wizard → 按 §二 IP1 参数配置 → Generate Output Products
- `IP Catalog` → Block Memory Generator → 按 §二 IP2 参数配置 (COE 选 `ip_sources/lcd_image.coe`) → Generate Output Products

### 4) 创建 Block Design
- `Create Block Design` → 加 PS7 → 配置 EMIO GPIO Width = 20
- 把 PS7 的 EMIO GPIO 端口 Make External
- 默认名 `GPIO_0` → 后续顶层需要修改, 见下一节

### 5) 顶层例化 PS7 (二选一)

**方案 A (推荐)**: 把 medical_glove_top.v 当作纯 PL 顶层, PS7 在 Block Design 里通过 EMIO 单向输出/输入信号, 然后在 Block Design 外部再写一个新顶层把两者拼在一起。

**方案 B**: 直接让 BD wrapper 当工程顶层, 在 BD 里例化 medical_glove_top 作为子 IP (需要 Package IP)。

**当前建议**: 调试期用 **方案 A** 快, 后续可重构。

### 6) 综合 / 实现 / 生成比特流
- `Run Synthesis` → 检查 timing
- `Run Implementation`
- `Generate Bitstream`

### 7) 导出硬件给 Vitis
- `File → Export → Export Hardware` → 勾选 Include bitstream
- 进入 `06_PS端软件/` 创建 Vitis 工程

---

## 四、模块层级图

```
                medical_glove_top.v  ★顶层★
                          │
   ┌──────────┬───────────┼───────────┬──────────┬──────────┐
   │          │           │           │          │          │
clock_reset key_debounce lcd_timing lcd_display touch_iic glove_fsm
   │                                              │          │
   └─►clk_wiz_0(IP)                               │          │
                                                  │          │
                                            pressure_iic  pwm_ctrl
                                                            │
                                                       safety_interlock
                                                            │
                                                  (pump_o/v1_o/v2_o)
                          │
                  axi_lite_reg ←──── EMIO ────► PS7 (ARM A9)
```

---

## 五、模块职责一览

| # | 模块 | 角色 | Arduino 类比 |
|---|------|------|-------------|
| 0 | medical_glove_top ★ | 顶层 | `.ino` 主文件 |
| 1 | clock_reset | 时钟生成 + 复位同步 | 内部定时器 |
| 2 | key_debounce | 物理按键 20ms 消抖 | 按键防抖代码 |
| 3 | lcd_timing | LCD 行场时序 | 屏库底层 |
| 4 | lcd_display | UI 渲染 | tft.fillRect |
| 5 | touch_iic | 触摸 IIC (早期方案, 最终走 PS EMIO 软 IIC, GT911) | Wire.h |
| 6 | pressure_iic | XGZP6857D 读气压 (官方规格书重写版, 带故障检测) | Wire.h 读 BMP |
| 7 | pwm_ctrl | 气泵软启动 PWM | analogWrite() |
| 8 | glove_fsm | 主状态机 | switch(state) |
| 9 | safety_interlock | 硬件安全联锁 | 物理保险丝 |
| 10 | axi_lite_reg | EMIO 接口 | Serial.print() |
| 11 | buzzer_ctrl | 蜂鸣器 2Hz 告警 (M14) | tone() |
| 12 | pressure_model | 仿真压力模型 (演示用) | 假传感器 |

---

## 六、代码风格约定

### 端口命名后缀
- `_i` — input
- `_o` — output
- `_io` — inout (仅 IIC 用)
- `_n` — 低电平有效 (如 `rst_n_i`)

### 信号命名中缀
- `_raw` — 原始信号
- `_clean` — 消抖/同步后
- `_sync` — 跨时钟域同步后

### 双版本约定
- 干净版 `xxx.v` (综合用)
- 教学版 `xxx_annotated.v` (每行注释, 仅作学习)

---

## 七、当前进度 (2026-08-16)

- ✅ 文件夹结构
- ✅ 顶层 medical_glove_top.v 双版本 (含 SIM_PRESSURE 仿真压力开关)
- ✅ 全部 13 个子模块双版本完成 (含 buzzer_ctrl / pressure_model)
- ✅ XDC 约束 (基于官方 NAVIGATOR_ZYNQ_IO.xdc, 已 1:1 对齐; false_path 用通配符 `clk_out*_clk_wiz_0*`)
- ✅ COE 图片资源 (ip_sources/lcd_image.coe, 200x175 RGB565)
- ✅ Vivado IP 生成 (clk_wiz_0 + lcd_image_rom)
- ✅ Block Design (PS7 + EMIO GPIO 64 位)
- ✅ 综合 + 实现 + Bitstream (已上板)
- ✅ 仿真 Testbench + Python 验证脚本 (sim/, 压力序列/BCD 字库/比特级 IIC 全过)
- ✅ 台架联调 (2026-08-04, 仿真压力模式气球演示成功)
- ⏳ 真实传感器闭环 (等重买 XGZP6857D 数字版, SIM_PRESSURE 改 0)

---

## 八、下一步行动

按以下顺序在 Vivado 里操作:

1. 新建工程 (xc7z020clg400-2)
2. 添加 11 个干净版 .v 文件 + medical_glove.xdc
3. 创建 IP: clk_wiz_0 + lcd_image_rom (按本文 §二配置)
4. 创建 Block Design 加 PS7
5. 写一个新顶层(top_wrapper.v)把 medical_glove_top 和 BD wrapper 连接
6. 跑综合, 看时序是否过, 修复警告
7. 实现 + 生成 bitstream
8. 导出 XSA 给 Vitis 用
