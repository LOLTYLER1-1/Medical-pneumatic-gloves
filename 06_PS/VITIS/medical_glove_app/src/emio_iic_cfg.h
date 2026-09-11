//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"���ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           emio_iic_cfg.h
// Last modified Date:  2026-05-21
// Last Version:        V2.0
// Descriptions:        EMIO GPIO �� XGpioPs ����Ŷ�Ӧ�޸�
//                      EMIO ����=64 ʱ��EMIO[54:57] ��Ӧ XGpioPs Pin 108:111
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef IIC_EMIO_CFG_
#define IIC_EMIO_CFG_

#include "xgpiops.h"

/* EMIO ����=64ʱ��XGpioPs Pin �� = 54 + EMIO ����
 * EMIO[54] = 54 + 54 = 108
 * EMIO[55] = 55 + 54 = 109
 * EMIO[56] = 56 + 54 = 110
 * EMIO[57] = 57 + 54 = 111
 */
#define EMIO_SCL_NUM    108     // EMIO[54] = SCL
#define EMIO_SDA_NUM    109     // EMIO[55] = SDA
#define EMIO_CT_RST_NUM 110     // EMIO[56] = CT_RST
#define EMIO_CT_INT_NUM 111     // EMIO[57] = CT_INT

void emio_init(void);

void  SDA_IN( void );
void  SDA_OUT( void );
void  IIC_SCL( u8 x );
void  IIC_SDA( u8 x );
u8  READ_SDA ( void );

void  CT_RST( u8 x );
void  INT_DIR( u8 x );
void  INT( u8 x );
u8  INT_RD( void );

#endif /* SCCB_EMIO_CFG_ */
