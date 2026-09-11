//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           ft5206.c
// Last modified Date:  2019/07/26 15:59:12
// Last Version:        V1.0
// Descriptions:        7����ݴ�����-FT5206/FT5426 ��������
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/07/26 15:59:18
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#include "xil_types.h"
#include "ft5206.h"
#include "touch.h"
#include "myiic.h"
#include "delay.h"
#include "main.h"
#include "emio_iic_cfg.h"

//��FT5206д��һ������
//reg:��ʼ�Ĵ�����ַ
//buf:���ݻ�������
//len:д���ݳ���
//����ֵ:0,�ɹ�;1,ʧ��.
u8 FT5206_WR_Reg(u16 reg,u8 *buf,u8 len)
{
    u8 i;
    u8 ret=0;
    IIC_Start();
    IIC_Send_Byte(FT_CMD_WR);   //����д����
    IIC_Wait_Ack();
    IIC_Send_Byte(reg&0XFF);    //���͵�8λ��ַ
    IIC_Wait_Ack();
    for(i=0; i<len; i++) {
        IIC_Send_Byte(buf[i]);  //������
        ret=IIC_Wait_Ack();
        if(ret)break;
    }
    IIC_Stop();                 //����һ��ֹͣ����
    return ret;
}

//��FT5206����һ������
//reg:��ʼ�Ĵ�����ַ
//buf:���ݻ�������
//len:�����ݳ���
void FT5206_RD_Reg(u16 reg,u8 *buf,u8 len)
{
    u8 i;
    IIC_Start();
    IIC_Send_Byte(FT_CMD_WR);                 //����д����
    IIC_Wait_Ack();
    IIC_Send_Byte(reg&0XFF);                  //���͵�8λ��ַ
    IIC_Wait_Ack();
    IIC_Start();
    IIC_Send_Byte(FT_CMD_RD);                 //���Ͷ�����
    IIC_Wait_Ack();
    for(i=0; i<len; i++) {
        buf[i] = IIC_Read_Byte( i == (len-1) ? 0 : 1 ); //������
    }

    IIC_Stop();//����һ��ֹͣ����
}

u8 CIP[5]; //������Ŵ���IC-GT911
//��ʼ��FT5206������
//����ֵ:0,��ʼ���ɹ�;1,��ʼ��ʧ��
u8 FT5206_Init(void)
{
    u8 temp[5];

    /* GT911 ��λʱ��: RST ������ɱ� INT ����Ϊ 0 ���ַ 0x5D */
    IIC_Init();
    INT_DIR(1);      // INT ���
    INT(0);          // INT = 0 (ѡ��ַ 0x5D)
    CT_RST(0);       // RST = 0
    delay_ms(20);    // T2 >= 10ms

    CT_RST(1);       // RST = 1, ������ɱ� INT=0 �� 0x5D
    delay_ms(60);    // T4 >= 50ms

    INT_DIR(0);      // INT ��Ϊ����
    delay_ms(100);

    /* ֱ�ӳ�ʼ�� GT911�������� FT5206 �汾���飬���� I2C ͨ��ʱ����ֵ��ƥ��
     * ǿ�� CIP="911"������ FT5206_Scan ���� GT911 ·�� */
    memcpy(CIP, "911\0", 4);

    /* ���� GT911 ����λ��������ģʽ */
    temp[0] = 0x02;
    GT9147_WR_Reg(GT_CTRL_REG, temp, 1);  // �� GT911 ����λ
    delay_ms(10);
    temp[0] = 0x00;
    GT9147_WR_Reg(GT_CTRL_REG, temp, 1);  // ��������ģʽ
    delay_ms(10);

    return 0;
}

const u16 FT5206_TPX_TBL[5]= {FT_TP1_REG,FT_TP2_REG,FT_TP3_REG,FT_TP4_REG,FT_TP5_REG};

//GT911����GT9xxϵ�У�����ֱ�ӵ���gt9147����غ궨��͵�����غ���
const u16 GT911_TPX_TBL[5]={GT_TP1_REG,GT_TP2_REG,GT_TP3_REG,GT_TP4_REG,GT_TP5_REG};
uint8_t g_gt_tnum = 5;      //Ĭ��֧�ֵĴ���������(5�㴥��)

//ɨ�败����(���ò�ѯ��ʽ)
//mode:0,����ɨ��.
//����ֵ:��ǰ����״̬.
//0,�����޴���;1,�����д���
u8 FT5206_Scan(u8 mode)
{
    u8 buf[4];
    u8 i=0;
    u8 res=0;
    u8 temp;
    u16 tempsta;
    static u8 t=0;//���Ʋ�ѯ���,�Ӷ�����CPUռ����
    t++;

    if((t%10)==0||t<10)//����ʱ,ÿ����10��CTP_Scan�����ż��1��,�Ӷ���ʡCPUʹ����
    {
        if(strcmp((char *)CIP,"911")==0) //����IC 911
        {
            GT9147_RD_Reg(GT_GSTID_REG,&mode,1);      //��ȡ������״̬
            if((mode&0X80)&&((mode&0XF)<=g_gt_tnum))
            {
                i = 0;
                GT9147_WR_Reg(GT_GSTID_REG,&i,1);    /* ���־ */
            }
        }
        else    //����IC FT5206
        {
            FT5206_RD_Reg(FT_REG_NUM_FINGER,&mode,1);//��ȡ�������״̬
        }

        if((mode&0XF)&&((mode&0XF)<=g_gt_tnum))
        {
            temp=0XFF<<(mode&0XF);                   //����ĸ���ת��Ϊ1��λ��,ƥ��tp_dev.sta����
            tempsta=tp_dev.sta;                      //���浱ǰ��tp_dev.staֵ
            tp_dev.sta=(~temp)|TP_PRES_DOWN|TP_CATH_PRES;
            tp_dev.x[g_gt_tnum-1]=tp_dev.x[0];       //���津��0������,���������һ����
            tp_dev.y[g_gt_tnum-1]=tp_dev.y[0];

            delay_ms(3); //��Ҫ����ʱ,��������Ϊ�а�������

            for(i=0;i<g_gt_tnum;i++)
            {
                if(tp_dev.sta&(1<<i))       //������Ч?
                {
                    if(strcmp((char *)CIP,"911")==0) //����IC 911
                    {
                        GT9147_RD_Reg(GT911_TPX_TBL[i],buf,4);   //��ȡXY����ֵ
                        if(tp_dev.touchtype&0X01) //����
                        {
                            tp_dev.y[i]=(((u16)buf[3]<<8)+buf[2]);
                            tp_dev.x[i]=(((u16)buf[1]<<8)+buf[0]);
                        }
                        else
                        {
                            tp_dev.x[i]=LCD_HEIGHT - (((u16)buf[3]<<8)+buf[2]);
                            tp_dev.y[i]=(((u16)buf[1]<<8)+buf[0]);
                        }
                    }
                    else
                    {
                        FT5206_RD_Reg(FT5206_TPX_TBL[i],buf,4); //��ȡXY����ֵ
                        if(tp_dev.touchtype&0X01)//����
                        {
                            tp_dev.y[i]=((u16)(buf[0]&0X0F)<<8)+buf[1];
                            tp_dev.x[i]=((u16)(buf[2]&0X0F)<<8)+buf[3];
                        }else
                        {
                            tp_dev.x[i]=LCD_HEIGHT-(((u16)(buf[0]&0X0F)<<8)+buf[1]);
                            tp_dev.y[i]=((u16)(buf[2]&0X0F)<<8)+buf[3];
                        }
                    }
                }
            }
            res=1;
            if(tp_dev.x[0] > LCD_HEIGHT || tp_dev.y[0] > LCD_WIDTH)  //�Ƿ�����(���곬����)
            {
                if((mode&0XF)>1)   // ��������������,�򸴵ڶ�����������ݵ���һ������.
                {
                    tp_dev.x[0]=tp_dev.x[1];
                    tp_dev.y[0]=tp_dev.y[1];
                    t=0;    // ����һ��,��������������10��,�Ӷ����������
                }
                else        // �Ƿ�����,����Դ˴�����(��ԭԭ����) 
                {
                    tp_dev.x[0]=tp_dev.x[g_gt_tnum-1];
                    tp_dev.y[0]=tp_dev.y[g_gt_tnum-1];
                    mode=0X80;
                    tp_dev.sta=tempsta;   // �ָ�tp_dev.sta 
                }
            }
            else t=0;      // ����һ��,��������������10��,�Ӷ���������� 
        }
    }

    if(strcmp((char *)CIP,"911")==0)        //����IC 911
    {
        if((mode&0X8F)==0X80)               //�޴����㰴��
        {
            if(tp_dev.sta&TP_PRES_DOWN)     //֮ǰ�Ǳ����µ�
            {
                tp_dev.sta&=~TP_PRES_DOWN;  //��ǰ����ɿ�
            }
            else                            //֮ǰ��û�б�����
            {
                tp_dev.x[0]=0xffff;
                tp_dev.y[0]=0xffff;
                tp_dev.sta&=0XE0;           //�������Ч���
            }
        }
    }
    else
    {
        if((mode&0X1F)==0) //�޴����㰴��
        {
            if(tp_dev.sta&TP_PRES_DOWN)    //֮ǰ�Ǳ����µ�
            {
                tp_dev.sta&=~TP_PRES_DOWN; //��ǰ����ɿ�
            }
            else                           //֮ǰ��û�б�����
            {
                tp_dev.x[0]=0xffff;
                tp_dev.y[0]=0xffff;
                tp_dev.sta&=0XE0;          //�������Ч���
            }
        }
    }

    if(t>240)t=10;//���´�10��ʼ����
    return res;
}
