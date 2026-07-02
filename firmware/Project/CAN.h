#pragma once

// Отправить qnt (<=8) байт из msg кадром CAN со стандартным идентификатором sfid.
void CAN_send_arr(unsigned char sfid, unsigned char* msg, unsigned char qnt);
