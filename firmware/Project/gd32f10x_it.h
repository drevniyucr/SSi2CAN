/*!
    \file    gd32f10x_it.h
    \brief   the header file of the ISR
*/

#ifndef GD32F10X_IT_H
#define GD32F10X_IT_H

#include "gd32f10x.h"

void NMI_Handler(void);
void HardFault_Handler(void);
void MemManage_Handler(void);
void BusFault_Handler(void);
void UsageFault_Handler(void);
void SVC_Handler(void);
void DebugMon_Handler(void);
void PendSV_Handler(void);
void SysTick_Handler(void);

#endif /* GD32F10X_IT_H */
