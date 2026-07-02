// =============================================================================
// CAN.c — передача кадров по CAN0 (модуль работает только на отправку).
// =============================================================================
#include "gd32f10x.h"
#include "CAN.h"

void CAN_send_arr(unsigned char sfid, unsigned char *msg, unsigned char qnt)
{
    can_trasnmit_message_struct transmit_message;
    unsigned char i;

    transmit_message.tx_sfid = sfid;
    transmit_message.tx_efid = 0x00;
    transmit_message.tx_ff   = CAN_FF_STANDARD;
    transmit_message.tx_ft   = CAN_FT_DATA;
    transmit_message.tx_dlen = qnt;
    for (i = 0; i < qnt; i++) transmit_message.tx_data[i] = msg[i];

    can_message_transmit(CAN0, &transmit_message);
}
