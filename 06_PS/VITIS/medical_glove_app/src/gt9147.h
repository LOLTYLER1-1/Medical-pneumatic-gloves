//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           gt9147
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        4.3����ݴ�����-GT9147 ��������
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/07/26 16:04:07
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef __GT9147_H
#define __GT9147_H

#include "xil_types.h"


//I2C��д����
#define GT_CMD_WR       0XBA        //д���� (GT911 addr 0x5D)
#define GT_CMD_RD       0XBB        //������ (GT911 addr 0x5D)

//GT9147 ���ּĴ�������
#define GT_CTRL_REG     0X8040      //GT9147���ƼĴ���
#define GT_CFGS_REG     0X8047      //GT9147������ʼ��ַ�Ĵ���
#define GT_CHECK_REG    0X80FF      //GT9147У��ͼĴ���
#define GT_PID_REG      0X8140      //GT9147��ƷID�Ĵ���

#define GT_GSTID_REG    0X814E      //GT9147��ǰ��⵽�Ĵ������
#define GT_TP1_REG      0X8150      //��һ�����������ݵ�ַ
#define GT_TP2_REG      0X8158      //�ڶ������������ݵ�ַ
#define GT_TP3_REG      0X8160      //���������������ݵ�ַ
#define GT_TP4_REG      0X8168      //���ĸ����������ݵ�ַ
#define GT_TP5_REG      0X8170      //��������������ݵ�ַ


u8 GT9147_Send_Cfg(u8 mode);                //����GT9147���ò���
u8 GT9147_WR_Reg(u16 reg,u8 *buf,u8 len);   //��GT9147д��һ������
void GT9147_RD_Reg(u16 reg,u8 *buf,u8 len); //��GT9147����һ������
u8 GT9147_Init(void);                       //��ʼ��GT9147������
u8 GT9147_Scan(u8 mode);                    //ɨ�败����(���ò�ѯ��ʽ)


#endif
