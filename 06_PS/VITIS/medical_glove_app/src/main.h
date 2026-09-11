//****************************************Copyright (c)***********************************//
//����ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"���ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           main
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        ������ͷ�ļ�
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/07/26 16:04:07
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef __MAIN_H__
#define __MAIN_H__

// LCD ID: 7�� 800x480 RGB��
#define lcd_id 0x4384

// �ֱ���
#define LCD_HEIGHT 480
#define LCD_WIDTH  800

// ������ɫ
#define MLCD_WHITE        0XFFFF
#define MLCD_BLACK        0X0000
#define MLCD_BLUE         0X001F
#define MLCD_BRED         0XF81F
#define MLCD_GRED         0XFFE0
#define MLCD_GBLUE        0X07FF
#define MLCD_RED          0XF800
#define MLCD_MAGENTA      0XF81F
#define MLCD_GREEN        0X07E0
#define MLCD_CYAN         0X7FFF
#define MLCD_YELLOW       0XFFE0
#define MLCD_BROWN        0XBC40
#define MLCD_BRRED        0XFC07
#define MLCD_GRAY         0X8430

#define MLCD_DARKBLUE     0X01CF
#define MLCD_LIGHTBLUE    0X7D7C
#define MLCD_GRAYBLUE     0X5458

#define MLCD_LIGHTGREEN   0X841F
#define MLCD_LGRAY        0XC618

#define MLCD_LGRAYBLUE    0XA651
#define MLCD_LBBLUE       0X2B12

#endif
