// =============================================================================
// rtos_v1.c — простой кооперативный планировщик периодических задач.
//
// RTOS_timer() тикает от TIMER1 (см. get_time_sys) и взводит задачи к запуску;
// RTOS_Dispatch() выполняет взведённые задачи в главном цикле.
// =============================================================================
#include "rtos_v1.h"
#include "timer.h"

static volatile task TaskArray[MAXnTASKS];

static void DeleteTask(unsigned char num)
{
    if (num < MAXnTASKS) {
        TaskArray[num].pFunc  = 0;
        TaskArray[num].delay  = 0;
        TaskArray[num].period = 0;
        TaskArray[num].run    = 0;
    }
}

// Тик планировщика: раз в RTOS_TIME тиков TIMER1 уменьшает задержки и взводит
// задачи, у которых задержка истекла.
void RTOS_timer(void)
{
    unsigned char i;

    if (!get_time_sys(RTOS_TIME)) return;

    for (i = 0; i < MAXnTASKS; i++) {
        if (!TaskArray[i].pFunc) continue;
        if (TaskArray[i].delay <= 1) {
            TaskArray[i].run   = 1;
            TaskArray[i].delay = TaskArray[i].period;
        } else {
            TaskArray[i].delay--;
        }
    }
}

// Зарегистрировать задачу taskfunc: первый запуск через taskdelay, далее каждые
// taskperiod тиков (taskperiod == 0 — одноразовая задача). Повторный вызов для
// уже зарегистрированной функции обновляет её тайминги.
void RTOS_SetTask(void (*taskfunc)(void), unsigned int taskdelay, unsigned int taskperiod)
{
    unsigned char i;

    for (i = 0; i < MAXnTASKS; i++) {
        if (TaskArray[i].pFunc == taskfunc) {
            TaskArray[i].delay  = taskdelay;
            TaskArray[i].period = taskperiod;
            TaskArray[i].run    = 0;
            return;
        }
    }
    for (i = 0; i < MAXnTASKS; i++) {
        if (!TaskArray[i].pFunc) {
            TaskArray[i].pFunc  = taskfunc;
            TaskArray[i].delay  = taskdelay;
            TaskArray[i].period = taskperiod;
            TaskArray[i].run    = 0;
            return;
        }
    }
}

// Выполнить взведённые задачи; одноразовые (period == 0) после запуска удалить.
void RTOS_Dispatch(void)
{
    unsigned char i;

    for (i = 0; i < MAXnTASKS; i++) {
        if (TaskArray[i].run) {
            TaskArray[i].run = 0;
            TaskArray[i].pFunc();
            if (!TaskArray[i].period) DeleteTask(i);
        }
    }
}
