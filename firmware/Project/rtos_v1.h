#pragma once

#define MAXnTASKS  50   // максимум одновременно зарегистрированных задач

typedef struct task {
    void (*pFunc)(void);              // функция задачи (0 — слот свободен)
    volatile unsigned int  delay;     // тиков до следующего запуска
    volatile unsigned int  period;    // период запуска в тиках (0 — одноразовая)
    volatile unsigned char run;       // задача взведена к выполнению
} task;

void RTOS_SetTask(void (*taskfunc)(void), unsigned int taskdelay, unsigned int taskperiod);
void RTOS_Dispatch(void);
void RTOS_timer(void);
