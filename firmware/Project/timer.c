// =============================================================================
// timer.c — TIMER1 как свободный счётчик для программного планировщика RTOS.
// =============================================================================
#include "gd32f10x.h"
#include "timer.h"

// Запуск TIMER1: делитель PRESC1, счёт вверх до 0xFFFF (используется как база
// времени в get_time_sys()).
void TIM1_Start(void)
{
    timer_parameter_struct timer_initpara;

    rcu_periph_clock_enable(RCU_TIMER1);
    timer_deinit(TIMER1);

    timer_struct_para_init(&timer_initpara);
    timer_initpara.prescaler        = PRESC1;
    timer_initpara.alignedmode      = TIMER_COUNTER_EDGE;
    timer_initpara.counterdirection = TIMER_COUNTER_UP;
    timer_initpara.period           = 0xFFFF;
    timer_initpara.clockdivision    = TIMER_CKDIV_DIV1;
    timer_init(TIMER1, &timer_initpara);

    timer_enable(TIMER1);
}

// Возвращает 1, когда с прошлого срабатывания прошло не менее time тиков TIMER1.
// Вызов с time == 0 сбрасывает точку отсчёта.
unsigned char get_time_sys(unsigned int time)
{
    static unsigned int t = 0;
    unsigned int tcnt = timer_counter_read(TIMER1);

    if (!time) t = tcnt;

    if ((tcnt - t) >= time) {
        t = tcnt;
        return 1;
    }
    return 0;
}
