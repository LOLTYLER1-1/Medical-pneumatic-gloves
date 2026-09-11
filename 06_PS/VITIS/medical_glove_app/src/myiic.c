//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           myiic
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        IIC ��������
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/07/26 16:04:03
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#include "myiic.h"
#include "emio_iic_cfg.h"

//����I2C�ٶȵ���ʱ
void CT_Delay(void)
{
    delay_us(2);
}

//��ʼ��IIC
void IIC_Init(void)
{
    IIC_SCL(1);
    IIC_SDA(1);
}

//����IIC��ʼ�ź�
void IIC_Start(void)
{
    SDA_OUT();   //sda�����
    IIC_SDA(1);
    IIC_SCL(1);
    CT_Delay();
    IIC_SDA(0);  //START�ź�:SCLΪ��ʱ��SDA�ɸ߱��
    CT_Delay();
    IIC_SCL(0);  //ǯסI2C���ߣ�׼�����ͻ��������
    CT_Delay();
}

//����IICֹͣ�ź�
void IIC_Stop(void)
{
    SDA_OUT();  //sda�����
    IIC_SCL(0);
    IIC_SDA(0); //STOP�ź�:SCLΪ��ʱ��SDA�ɵͱ��
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    IIC_SDA(1); //����I2C���߽����ź�
    CT_Delay();
}

//�ȴ�Ӧ���źŵ���
//����ֵ��1������Ӧ��ʧ��
//0������Ӧ��ɹ�
u8 IIC_Wait_Ack(void)
{
    u8 ucErrTime=0;
    SDA_IN();      //SDA����Ϊ����
    IIC_SDA(1);
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    while( READ_SDA() ) {
        ucErrTime++;
        if(ucErrTime>250) {
            IIC_Stop();
            return 1;
        }
    }
    IIC_SCL(0);//ʱ�����0
    CT_Delay();
    return 0;
}

//����ACKӦ��
void IIC_Ack(void)
{
    IIC_SCL(0);
    SDA_OUT();
    IIC_SDA(0);
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    IIC_SCL(0);
    CT_Delay();
}

//������ACKӦ��
void IIC_NAck(void)
{
    IIC_SCL(0);
    SDA_OUT();
    IIC_SDA(1);
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    IIC_SCL(0);
    CT_Delay();
}

//IIC����һ���ֽ�
//���شӻ�����Ӧ��
//1����Ӧ��
//0����Ӧ��
void IIC_Send_Byte(u8 txd)
{
    u8 t;
    SDA_OUT();
    IIC_SCL(0);//����ʱ�ӿ�ʼ���ݴ���
    for(t=0; t<8; t++) {
        IIC_SDA((txd&0x80)>>7);
        txd<<=1;
        CT_Delay();
        IIC_SCL(1);
        CT_Delay();
        IIC_SCL(0);
        CT_Delay();
    }
}

//��1���ֽڣ�ack=1ʱ������ACK��ack=0������nACK
u8 IIC_Read_Byte(unsigned char ack)
{
    unsigned char i,receive=0;
    SDA_IN();//SDA����Ϊ����
    for(i=0; i<8; i++ ) {
        IIC_SCL(0);
        CT_Delay();
        IIC_SCL(1);
        receive<<=1;
        if( READ_SDA() )
            receive++;
        CT_Delay();
    }
    if (!ack)
        IIC_NAck();//����nACK
    else
        IIC_Ack(); //����ACK
    return receive;
}
