#-----------------------------------------------------------------------------
# Vivado BD EMIO GPIO 三态改造 TCL 脚本
# 用途: 在当前 BD 基础上添加 GPIO_T_0 端口，使 EMIO[54:57] 支持双向 I/O
#
# 使用方法:
#   1. 在 Vivado 中打开 medical_project 工程
#   2. 确保 Block Design (system.bd) 已打开
#   3. 在 Tcl Console 中运行: source vivado_bd_emio_fix.tcl
#   4. 重新 Generate Bitstream
#
# 原理:
#   - 保留现有 GPIO_I_0[63:0] / GPIO_O_0[63:0]（气泵控制不受影响）
#   - 新增 GPIO_T_0[63:0]（三态控制信号）
#   - 在 system_top.v 中对 EMIO[54:57] 手动实例化 IOBUF
#   - PS 软件通过 XGpioPs_SetOutputEnablePin() 控制方向
#     内部会反映到 GPIO_T 信号上（1=输入/高阻, 0=输出）
#-----------------------------------------------------------------------------

puts "========================================"
puts "  EMIO GPIO 三态改造开始"
puts "========================================"

# Step 0: 确认 BD 已打开
set bd_designs [get_bd_designs -quiet]
if { [llength $bd_designs] == 0 } {
    puts "错误: 没有打开的 Block Design"
    puts "请在 Vivado 中点击 'Open Block Design' 后再运行此脚本"
    return
}
set bd_design [lindex $bd_designs 0]
puts "当前 BD: $bd_design"

# 切换到当前 BD 上下文
current_bd_design $bd_design

# Step 2: 检查现有 GPIO 端口
puts "Step 2: 检查现有 GPIO 端口..."
set gpio_i_port [get_bd_ports -quiet GPIO_I_0]
set gpio_o_port [get_bd_ports -quiet GPIO_O_0]

if { [llength $gpio_i_port] == 0 || [llength $gpio_o_port] == 0 } {
    puts "错误: 未找到 GPIO_I_0 或 GPIO_O_0，请确认 BD 配置正确"
    return
}
puts "  GPIO_I_0 存在 (方向=[get_property DIR $gpio_i_port], 宽度=[get_property LEFT $gpio_i_port]:[get_property RIGHT $gpio_i_port])"
puts "  GPIO_O_0 存在 (方向=[get_property DIR $gpio_o_port], 宽度=[get_property LEFT $gpio_o_port]:[get_property RIGHT $gpio_o_port])"

# Step 3: 检查是否已有 GPIO_T_0
puts "Step 3: 检查 GPIO_T_0..."
set gpio_t_port [get_bd_ports -quiet GPIO_T_0]
if { [llength $gpio_t_port] > 0 } {
    puts "  GPIO_T_0 已存在，跳过创建"
} else {
    puts "  GPIO_T_0 不存在，开始创建..."

    # Step 4: 创建 GPIO_T_0 外部端口
    puts "Step 4: 创建 GPIO_T_0 外部端口..."
    create_bd_port -dir O -from 63 -to 0 GPIO_T_0
    puts "  已创建 GPIO_T_0 (output [63:0])"

    # Step 5: 连接 GPIO_T_0 到 processing_system7_0/GPIO_T
    puts "Step 5: 连接 GPIO_T_0 到 processing_system7_0/GPIO_T..."
    set ps7_gpio_t [get_bd_pins -quiet processing_system7_0/GPIO_T]

    if { [llength $ps7_gpio_t] == 0 } {
        puts "错误: 未找到 processing_system7_0/GPIO_T 引脚"
        puts "请确认 PS7 配置中 EMIO GPIO 已使能"
        return
    }

    connect_bd_net -net gpio_t_0_net [get_bd_ports GPIO_T_0] $ps7_gpio_t
    puts "  已连接 GPIO_T_0 -> processing_system7_0/GPIO_T"
}

# Step 6: 验证连接
puts "Step 6: 验证连接..."
set conn_check [get_bd_nets -quiet -of_objects [get_bd_pins processing_system7_0/GPIO_T]]
if { [llength $conn_check] > 0 } {
    puts "  GPIO_T 已正确连接"
} else {
    puts "  警告: GPIO_T 连接可能有问题"
}

# Step 7: 保存 BD
puts "Step 7: 保存 BD..."
save_bd_design
puts "  BD 已保存"

# Step 8: 重新生成 wrapper
puts "Step 8: 重新生成 system_wrapper..."
set wrapper_file [get_files -quiet system_wrapper.v]
if { [llength $wrapper_file] > 0 } {
    make_wrapper -files [get_files system.bd] -top
    # 找到新生成的 wrapper
    set gen_dir [get_property DIRECTORY [current_project]]
    set new_wrapper [glob -nocomplain "$gen_dir/*.srcs/*/bd/system/hdl/system_wrapper.v"]
    if { [llength $new_wrapper] > 0 } {
        # 读取新文件内容
        set fh [open [lindex $new_wrapper 0] r]
        set content [read $fh]
        close $fh
        # 写回旧文件
        set old_wrapper [lindex $wrapper_file 0]
        set fh [open $old_wrapper w]
        puts $fh $content
        close $fh
        puts "  wrapper 已更新: $old_wrapper"
    }
} else {
    puts "  未找到现有 wrapper，将在 Generate 时自动创建"
}

puts ""
puts "========================================"
puts "  EMIO GPIO 三态改造完成"
puts "========================================"
puts ""
puts "新的 system_wrapper 端口:"
puts "  input  [63:0] GPIO_I_0   (现有，不变)"
puts "  output [63:0] GPIO_O_0   (现有，不变)"
puts "  output [63:0] GPIO_T_0   (新增，三态控制)"
puts ""
puts "system_top.v 中需要:"
puts "  1. 声明 wire [63:0] emio_gpio_t 连接 GPIO_T_0"
puts "  2. 对 EMIO[54:57] 实例化 IOBUF 原语"
puts "  3. IOBUF 的 .T 端连接 emio_gpio_t[54:57]"
puts ""
puts "下一步操作:"
puts "  1. 在 Vivado 中点击 'Validate Design' 验证 BD"
puts "  2. 运行 'Generate Bitstream' 重新生成比特流"
puts "  3. 导出 Hardware (Include bitstream)"
