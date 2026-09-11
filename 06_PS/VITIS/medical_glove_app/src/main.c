#include <stdio.h>
#include "xparameters.h"
#include "xgpiops.h"
#include "sleep.h"
#include "touch.h"
#include "emio_iic_cfg.h"

#define PSGPIO_DEVICE_ID XPAR_PS7_GPIO_0_DEVICE_ID
#define PS_LED0_MIO      7
#define PS_LED1_MIO      8

/* ==========================================================================
 * EMIO GPIO 映射 (与 PL system_top.v 严格一致)
 *   XGpioPs Pin = 54 + EMIO 索引;  XGpioPs bank2 = EMIO[31:0]
 *   输出 (PS->PL):  EMIO[0] = grip_req, EMIO[1] = release_req
 *                   EMIO[17:2] = setpoint (单位 0.01kPa)
 *   输入 (PL->PS):  EMIO[15:0]  = pressure (0.01kPa)
 *                   EMIO[18:16] = fsm_state, EMIO[19] = safety_trigger
 *                   EMIO[20]    = sensor_fault
 * 用 bank2 整bank 读写: 一次 32bit 原子操作, 避免逐位写中间态。
 * ========================================================================== */
#define EMIO_BANK        2
#define BIT_GRIP         0x1u        /* bank2 bit0 = EMIO[0] */
#define BIT_RELEASE      0x2u        /* bank2 bit1 = EMIO[1] */
#define SETPOINT_SHIFT   2           /* setpoint 从 bit2 开始 */

/* 目标压力, 单位 0.01kPa: 5000 = 50.00 kPa
 * 允许范围 3000~8000 (30~80kPa); 必须 > FSM 回差 200, 且 < 安全联锁 8000 */
#define SETPOINT_X100_KPA  5000

/* 触摸区域 (基于 tp_dev 坐标系, 实测映射):
 *   物理X = tp_dev.y (0~800, 左->右),  物理Y = 480 - tp_dev.x (0~480, 上->下)
 * LCD 布局: 左半浅绿 = 收缩(GRIP), 右半浅橙 = 舒张(RELEASE), 顶部 y<50 状态条
 * 有效区 = 左右两个大半屏 (大触摸目标, 方便手部无力患者), 仅排除状态条/下边缘
 */
#define ZONE_MID_X      400   /* tp_dev.y < 400 = 左半屏(收缩), >=400 右半(舒张) */
#define ZONE_TX_MAX     430   /* tp_dev.x < 430 -> 物理Y > 50, 排除顶部状态条 */
#define ZONE_TX_MIN      10   /* tp_dev.x > 10  -> 物理Y < 470, 排除下边缘 */

/* ==========================================================================
 * 无阻塞 DCC 打印 (2026-08-02 重要修正)
 * 本 BSP 的 stdout = JTAG DCC (ps7_coresight_comp_0): 标准 printf 会
 * 忙等 DCC 发送空位, 而"空位"需要调试器经 JTAG 读走数据才会释放 ——
 * 脱机运行(不接调试器)时, printf 第 2 个字符起就永久卡死整个程序!
 * 所以绝不能用 printf, 必须逐字符带超时发送: 调试器在线时正常显示,
 * 脱机时自动丢弃, 绝不阻塞。指令序列与 BSP 驱动 xcoresightpsdcc.c 一致。
 * ========================================================================== */
#define DCC_STATUS_TXFULL  (1u << 29)   /* DBGDSCR TX 满标志 */
#define DCC_TIMEOUT        20000u       /* 每字符忙等上限 (约 300us @667MHz) */

static inline u32 dcc_status(void)
{
    u32 s;
    asm volatile("mrc p14, 0, %0, c0, c1, 0" : "=r" (s) :: "cc");
    return s;
}

/* 发送 1 字符; 返回 0 = 超时(无人接收, 放弃) */
static int dcc_putc(char c)
{
    u32 timeout = DCC_TIMEOUT;
    while (dcc_status() & DCC_STATUS_TXFULL) {
        if (timeout-- == 0u)
            return 0;
    }
    asm volatile("mcr p14, 0, %0, c0, c5, 0" :: "r" ((u32)(u8)c) : "cc");
    return 1;
}

static void dcc_puts(const char *s)
{
    while (*s) {
        if (!dcc_putc(*s++))
            return;                 /* 无人接收: 丢弃本条剩余内容 */
    }
}

static XGpioPs GpioPs;
static u32     emio_shadow = 0;   /* bank2 输出影子寄存器 */

static void ps_led0(int on) { XGpioPs_WritePin(&GpioPs, PS_LED0_MIO, on ? 1 : 0); }
static void ps_led1(int on) { XGpioPs_WritePin(&GpioPs, PS_LED1_MIO, on ? 1 : 0); }

/* 影子寄存器 -> 硬件: 一次 32bit 原子写入 */
static void emio_apply(void)
{
    XGpioPs_Write(&GpioPs, EMIO_BANK, emio_shadow);
}

/* 写目标压力 (bit[17:2]), 不影响 grip/release 两位 */
static void ps_write_setpoint(u16 sp_x100kpa)
{
    emio_shadow = (emio_shadow & 0x3u) | (((u32)sp_x100kpa) << SETPOINT_SHIFT);
    emio_apply();
}

/* 写请求位 (bit[1:0]): 0=无, BIT_GRIP=抓握, BIT_RELEASE=释放; 不影响 setpoint */
static void ps_write_request(u32 req_bits)
{
    emio_shadow = (emio_shadow & ~0x3u) | (req_bits & 0x3u);
    emio_apply();
}

int main(void)
{
    XGpioPs_Config *psCfg = XGpioPs_LookupConfig(PSGPIO_DEVICE_ID);
    XGpioPs_CfgInitialize(&GpioPs, psCfg, psCfg->BaseAddr);

    /* LED 初始化 */
    XGpioPs_SetDirectionPin(&GpioPs, PS_LED0_MIO, 1);
    XGpioPs_SetOutputEnablePin(&GpioPs, PS_LED0_MIO, 1);
    XGpioPs_SetDirectionPin(&GpioPs, PS_LED1_MIO, 1);
    XGpioPs_SetOutputEnablePin(&GpioPs, PS_LED1_MIO, 1);

    /* EMIO[0..17] = XGpioPs pin 54..71, 全部设为输出 (grip/release/setpoint) */
    for (int i = 0; i < 18; i++) {
        XGpioPs_SetDirectionPin(&GpioPs, 54 + i, 1);
        XGpioPs_SetOutputEnablePin(&GpioPs, 54 + i, 1);
    }

    ps_led0(0);
    ps_led1(0);

    /* 请求清零 + 写入目标压力 (修复: 旧代码从未写 setpoint, FSM 目标恒 0) */
    emio_shadow = 0;
    ps_write_setpoint(SETPOINT_X100_KPA);

    emio_init();   /* 触摸 I2C 口 (EMIO[54:57] = pin 108~111) */

    /* 启动信号：LED0 快闪 3 次 */
    for (int i = 0; i < 3; i++) {
        ps_led0(1); usleep(100000);
        ps_led0(0); usleep(100000);
    }

    /* 注意: FT5206_Init/S_scan 实际驱动的是 GT911/9147 ("911" 分支),
     * 函数名是历史遗留; 触摸通信 2026-05-21 已在硬件验证, 勿动 */
    TP_Init();

    /* TP_Init 完成：LED1 亮 2 秒 */
    ps_led1(1); usleep(2000000); ps_led1(0);

    dcc_puts("glove app start, setpoint = 50.00 kPa\r\n");

    const char *state_name[8] = { "IDLE", "GRIP", "HOLD", "RELEASE",
                                  "EMERGENCY", "?", "?", "?" };
    int tick = 0;
    int heartbeat = 0;
    char msg[96];

    while (1) {
        tp_dev.scan(0);

        if (tp_dev.sta & TP_PRES_DOWN) {
            ps_led1(1);  /* 触摸中，LED1 亮 */

            u16 tx = tp_dev.x[0];  /* 0~480, 物理Y = 480 - tx */
            u16 ty = tp_dev.y[0];  /* 0~800 = 物理X, 越大越靠右 */

            if (tx > ZONE_TX_MIN && tx < ZONE_TX_MAX) {
                /* 左半屏(浅绿) = 收缩, 右半屏(浅橙) = 舒张, 与 LCD 显示一致 */
                if (ty < ZONE_MID_X)
                    ps_write_request(BIT_GRIP);
                else
                    ps_write_request(BIT_RELEASE);
            }
        } else {
            ps_led1(0);  /* 无触摸，LED1 灭 */
            /* 触摸抬起清零请求; GRIP/HOLD/RELEASE 状态由 PL FSM 自保持 */
            ps_write_request(0);
        }

        /* 每 500ms: 读 PL 反馈 + LED0 状态指示 + 无阻塞打印 */
        if (++tick >= 25) {
            tick = 0;
            u32 bank2  = XGpioPs_Read(&GpioPs, EMIO_BANK);
            u16 pres   = bank2 & 0xFFFF;
            u8  st     = (bank2 >> 16) & 0x7;
            u8  safety = (bank2 >> 19) & 0x1;
            u8  fault  = (bank2 >> 20) & 0x1;

            /* LED0: 传感器故障时常亮(醒目), 正常时 1Hz 心跳(证明程序活着) */
            if (fault) {
                ps_led0(1);
            } else {
                heartbeat ^= 1;
                ps_led0(heartbeat);
            }

            snprintf(msg, sizeof(msg), "P=%d.%02dkPa state=%s safety=%d fault=%d\r\n",
                     pres / 100, pres % 100, state_name[st], safety, fault);
            dcc_puts(msg);
            if (fault)
                dcc_puts("!! 气压传感器通信失败, 已自动停泵泄气, 请检查传感器接线\r\n");
        }

        usleep(20000);  /* 20ms 轮询 */
    }
    return 0;
}
