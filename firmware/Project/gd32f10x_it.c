/*!
    \file    gd32f10x_it.c
    \brief   interrupt service routines
*/

#include "gd32f10x_it.h"

void NMI_Handler(void)        { }
void SVC_Handler(void)        { }
void DebugMon_Handler(void)   { }
void PendSV_Handler(void)     { }
void SysTick_Handler(void)    { }

// Необрабатываемые отказы — остановиться для анализа в отладчике.
void HardFault_Handler(void)  { while (1) { } }
void MemManage_Handler(void)  { while (1) { } }
void BusFault_Handler(void)   { while (1) { } }
void UsageFault_Handler(void) { while (1) { } }
