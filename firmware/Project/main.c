// =============================================================================
// main.c — прошивка модуля SRL-8SSI-CAN.
//
// Задачи: инициализация периферии, стартовый самотест моста encoder_hub (FPGA)
// по SPI, периодический опрос позиций SSI-энкодеров и трансляция их по CAN,
// индикация результата самотеста светодиодом SYS.
// =============================================================================
#include "gd32f10x.h"

#include "configuration.h"
#include "timer.h"
#include "rtos_v1.h"
#include "pin.h"
#include "CAN.h"
#include "fpga_test.h"
#include "spi_fpga.h"

// SFID кадра с результатом теста/опроса FPGA (наблюдать анализатором CAN).
#define SFID_FPGA_STATUS   0x40

// Итог стартового самотеста FPGA: 0 = все проверки прошли.
// Виден в отладчике; также определяет режим мигания светодиода.
volatile unsigned int g_fpga_selftest_failed = 0xFFFF;

// Периодический опрос позиций энкодеров по SPI и трансляция первой позиции в CAN.
static void func_fpga_poll(void)
{
    unsigned char msg[8];

    fpga_test_poll_once();   // триггер опроса + чтение status/error/позиций

    // CAN-кадр: [status][error_mask][valid_mask][fault_mask][pos0 32-bit BE]
    msg[0] = g_fpga.status;
    msg[1] = g_fpga.error_mask;
    msg[2] = g_fpga.valid_mask;
    msg[3] = g_fpga.fault_mask;
    msg[4] = (unsigned char)(g_fpga.pos[0] >> 24);
    msg[5] = (unsigned char)(g_fpga.pos[0] >> 16);
    msg[6] = (unsigned char)(g_fpga.pos[0] >> 8);
    msg[7] = (unsigned char)(g_fpga.pos[0]);
    CAN_send_arr(SFID_FPGA_STATUS, msg, 8);
}

// Индикация результата самотеста светодиодом SYS:
//   ОК — короткая вспышка раз в ~2 с; ОШИБКА — частое мигание ~5 Гц.
static void func_led(void)
{
    static unsigned int t = 0;

    if (g_fpga_selftest_failed == 0) {
        if (++t >= 20) t = 0;
        if (t == 0)      LED_SYS_ON();
        else             LED_SYS_OFF();
    }
    else {
        (++t & 1) ? LED_SYS_ON() : LED_SYS_OFF();
    }
}

int main(void)
{
    long delay = 0;

    RCC_Configuration();
    while (++delay < FOSC / 5) { ; }   // грубая пауза на стабилизацию питания

    GPIO_Configuration();
    CAN_Configuration();
    LED_SYS_ON();
    TIM1_Start();

    // --- Инициализация моста encoder_hub (FPGA) по SPI0 ---
    // rst FPGA заведён на внешнюю кнопку (см. spi_fpga.h): MCU им не управляет,
    // fpga_reset_release() — пустышка, готовность ловим опросом NOP (== 0x55).
    fpga_spi_init();
    fpga_reset_release();
    fpga_wait_ready(2000);

    // Однократный полный самотест всех команд протокола encoder_hub.
    // Подробности результата — в g_fpga (см. fpga_test.h).
    g_fpga_selftest_failed = fpga_test_run();

    RTOS_SetTask(func_fpga_poll, 0, RTOS_TIME_0S1);   // опрос SSI + CAN, 100 мс
    RTOS_SetTask(func_led, 0, RTOS_TIME_50MS);  // индикация самотеста

    while (1) {
        RTOS_Dispatch();
        RTOS_timer();
    }
}
