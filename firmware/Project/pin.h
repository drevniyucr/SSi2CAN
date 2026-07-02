#pragma once

#include "gd32f10x.h"

// Светодиод SYS на PC12 (активный уровень — высокий).
#define LED_SYS_ON()   (GPIO_BOP(GPIOC) = GPIO_PIN_12)
#define LED_SYS_OFF()  (GPIO_BC(GPIOC)  = GPIO_PIN_12)
