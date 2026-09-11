`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// clock_reset.v   Rev 2026-08-02
// 修订: 新增 rst_n_sync_pclk_o。原 rst_n_sync_o 只在 100MHz 域同步, 直接给
//       33MHz LCD 域用, 复位释放沿未对 33M 同步; 现两个时钟域各自同步释放。
//-----------------------------------------------------------------------------
module clock_reset (
    input  wire sys_clk_i,
    input  wire sys_rst_n_i,

    output wire clk_100m_o,
    output wire pclk_33m_o,
    output wire rst_n_sync_o,        /* 100MHz 域同步复位(低有效) */
    output wire rst_n_sync_pclk_o    /* 33MHz 域同步复位(低有效) */
);

    wire locked;
    wire mmcm_rst = ~sys_rst_n_i;

    clk_wiz_0 u_clk_wiz_0 (
        .clk_in1  (sys_clk_i),
        .reset    (~sys_rst_n_i),
        .clk_out1 (clk_100m_o),
        .clk_out2 (pclk_33m_o),
        .locked   (locked)
    );

    wire      raw_rst_n = sys_rst_n_i & locked;

    /* 100MHz 域: 异步复位, 同步释放 */
    reg [2:0] rst_sync_r;
    always @(posedge clk_100m_o or negedge raw_rst_n) begin
        if (!raw_rst_n)
            rst_sync_r <= 3'b000;
        else
            rst_sync_r <= {rst_sync_r[1:0], 1'b1};
    end
    assign rst_n_sync_o = rst_sync_r[2];

    /* 33MHz 域: 异步复位, 同步释放 */
    reg [2:0] rst_sync_pclk_r;
    always @(posedge pclk_33m_o or negedge raw_rst_n) begin
        if (!raw_rst_n)
            rst_sync_pclk_r <= 3'b000;
        else
            rst_sync_pclk_r <= {rst_sync_pclk_r[1:0], 1'b1};
    end
    assign rst_n_sync_pclk_o = rst_sync_pclk_r[2];

endmodule
