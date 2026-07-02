#pragma once

void RCC_Configuration(void);    // тактирование: SYSCLK 36 МГц от HXTAL/PLL
void GPIO_Configuration(void);   // LED, линии CAN0
void CAN_Configuration(void);    // CAN0, 125 кбит/с, только передача
