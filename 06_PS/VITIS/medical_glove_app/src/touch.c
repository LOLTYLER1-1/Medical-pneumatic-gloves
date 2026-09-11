//*****************************************************************************
// File name:           touch.c
// Last modified Date:  2026-08-02
// Descriptions:        Touch panel top level (capacitive, GT911/GT9147 chip)
//
// Rev 2026-08-02:
//   - removed dead TP_Scan(): it was never called (tp_dev.scan was already
//     bound to FT5206_Scan) and contained debug printf
//   - tp_dev.scan is now bound to FT5206_Scan directly at initialization
//   - TP_Init returns u8 to match the struct function pointer type
//
// NOTE: FT5206_Init / FT5206_Scan actually drive the GT911/GT9147 chip
//       (the "911" branch inside ft5206.c). The names are historical.
//       Touch communication was verified on hardware 2026-05-21 - DO NOT
//       change the driver call flow.
//*****************************************************************************

#include "touch.h"
#include "delay.h"
#include "stdlib.h"
#include "math.h"
#include <stdio.h>
#include "main.h"
#include "xil_types.h"
#include "emio_iic_cfg.h"

_m_tp_dev tp_dev = {
    TP_Init,        /* init function */
    FT5206_Scan,    /* scan function (GT911/9147 path inside ft5206.c) */
    0,              /* x[]  */
    0,              /* y[]  */
    0,              /* sta  */
    0,              /* touchtype */
};

//*****************************************************************************
// Touch panel init
// FT5206_Init() performs the GT911-style reset sequence (INT low at RST
// rising edge selects I2C addr 0x5D) and soft-resets the chip.
// return: 0 = ok
//*****************************************************************************
u8 TP_Init(void)
{
    FT5206_Init();              /* actually initializes GT911/9147 */
    tp_dev.touchtype |= 0X80;   /* capacitive panel flag */
    return 0;
}
