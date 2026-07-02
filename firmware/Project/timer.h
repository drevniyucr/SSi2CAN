#pragma once

#define FOSC    36000000      // SYSCLK, Гц
#define PRESC1  1024          // делитель TIMER1

// Тик планировщика RTOS: TIMER1 = FOSC/PRESC1, RTOS_TIME задаёт период в тиках.
#define TIME_2MS        (2 * (FOSC / PRESC1) / 1000)
#define RTOS_TIME       TIME_2MS   // база планировщика ≈ 2 мс
#define RTOS_TIME_STEP  2          // мс на один шаг delay/period задач

// Периоды задач в шагах планировщика (RTOS_TIME_STEP мс каждый).
#define RTOS_TIME_50MS  (50  / RTOS_TIME_STEP)
#define RTOS_TIME_0S1   (100 / RTOS_TIME_STEP)

void          TIM1_Start(void);
unsigned char get_time_sys(unsigned int time);
