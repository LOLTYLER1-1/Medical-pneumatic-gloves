//=============================================================================
// File        : clock_reset_annotated.v   ★教学版（不要加入工程综合）★
// 用 Arduino 类比:
//   - clk_in1 50MHz 像 Arduino 的 16MHz 晶振
//   - PLL 把 50 倍频/分频成 100MHz 和 33MHz (像超频或分频)
//   - rst_n_sync_o / rst_n_sync_pclk_o 是两个时钟域各自的"能用的复位信号"
//
// Rev 2026-08-02 修订:
//   ★ 新增 rst_n_sync_pclk_o (33MHz 域同步复位)
//     旧版只有一个 100MHz 域同步的 rst_n_sync_o, 直接拿去复位 33MHz 的
//     LCD 模块 —— 复位"释放沿"对 33MHz 时钟是异步的, 有亚稳态风险。
//     现在每个时钟域各配一套同步释放电路, 各管各的。
//=============================================================================

`timescale 1ns / 1ps                                    // 仿真时间精度

module clock_reset (
    input  wire sys_clk_i,                              // 输入 50 MHz 晶振
    input  wire sys_rst_n_i,                            // 板上 KEY_RST 按键(低电平有效)

    output wire clk_100m_o,                             // 输出 100 MHz, 给逻辑/IIC/状态机用
    output wire pclk_33m_o,                             // 输出 33 MHz, 专给 LCD 像素时钟
    output wire rst_n_sync_o,                           // 100MHz 域同步复位(低有效)
    output wire rst_n_sync_pclk_o                       // 33MHz 域同步复位(低有效)
);

    wire locked;                                        // PLL 锁定信号(1=输出时钟可信)
    wire mmcm_rst = ~sys_rst_n_i;                       // clk_wiz IP 的 reset 是高有效, 需取反

    // === 例化 Vivado 自动生成的 Clocking Wizard IP ===
    // 这个 IP 必须先在 Vivado 中 "IP Catalog" → Clocking Wizard 添加
    // 配置: clk_in1=50MHz, clk_out1=100MHz, clk_out2=33MHz
    clk_wiz_0 u_clk_wiz_0 (
        .clk_in1  (sys_clk_i),                          // 输入 50MHz
        .reset    (~sys_rst_n_i),                       // 复位, 高有效, 所以取反 sys_rst_n_i
        .clk_out1 (clk_100m_o),                         // 输出 1: 100MHz
        .clk_out2 (pclk_33m_o),                         // 输出 2: 33MHz
        .locked   (locked)                              // PLL 锁定标志
    );

    // 总复位条件: 按键按下 或 PLL 还没锁定 → 复位
    wire raw_rst_n = sys_rst_n_i & locked;

    // === 异步复位同步释放电路 #1 (100MHz 域) ===
    // 目的: 复位信号从外部按键来, 异步; 但释放复位时必须和本域时钟同步
    //       避免亚稳态(metastability)
    // 类比: Arduino 的按键消抖, 但这里只关心"释放抖动"
    reg [2:0] rst_sync_r;                               // 3 级移位寄存器
    always @(posedge clk_100m_o or negedge raw_rst_n) begin // 时钟上升沿 或 复位下降沿
        if (!raw_rst_n)                                 // 任何一项复位条件: 清零
            rst_sync_r <= 3'b000;
        else                                            // 正常运行: 左移, 末位补 1
            rst_sync_r <= {rst_sync_r[1:0], 1'b1};      // 3 个时钟周期后稳定为 111
    end
    assign rst_n_sync_o = rst_sync_r[2];                // 取最后一级输出(已稳定)

    // === 异步复位同步释放电路 #2 (33MHz 域, 2026-08-02 新增) ===
    // 结构完全一样, 只是采样时钟换成 LCD 像素时钟
    reg [2:0] rst_sync_pclk_r;
    always @(posedge pclk_33m_o or negedge raw_rst_n) begin
        if (!raw_rst_n)
            rst_sync_pclk_r <= 3'b000;
        else
            rst_sync_pclk_r <= {rst_sync_pclk_r[1:0], 1'b1};
    end
    assign rst_n_sync_pclk_o = rst_sync_pclk_r[2];

endmodule
