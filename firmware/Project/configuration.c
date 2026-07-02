// =============================================================================
// configuration.c — тактирование, GPIO и CAN модуля SRL-8SSI-CAN.
// =============================================================================
#include "gd32f10x.h"
#include "configuration.h"

// ------------------------------- Тактирование -------------------------------
// SYSCLK = 36 МГц от HXTAL через PLL. APB1 = SYSCLK/2, остальное = SYSCLK.
void RCC_Configuration(void)
{
    uint32_t timeout = 0U;

    rcu_system_clock_source_config(RCU_CKSYSSRC_IRC8M);
    rcu_deinit();

    // Запуск HXTAL и ожидание стабилизации (с тайм-аутом).
    RCU_CTL |= RCU_CTL_HXTALEN;
    do {
        timeout++;
    } while ((0U == (RCU_CTL & RCU_CTL_HXTALSTB)) &&
        (HXTAL_STARTUP_TIMEOUT != timeout));

    if (0U == (RCU_CTL & RCU_CTL_HXTALSTB)) {
        while (1) { ; }   // HXTAL не завёлся — дальше идти нельзя
    }

    RCU_CFG0 |= RCU_AHB_CKSYS_DIV1;    // AHB  = SYSCLK
    RCU_CFG0 |= RCU_APB2_CKAHB_DIV1;   // APB2 = AHB
    RCU_CFG0 |= RCU_APB1_CKAHB_DIV1;   // APB1 = AHB/2

    // CK_PLL = (HXTAL/2) * 9 = 36 МГц
    RCU_CFG0 &= ~(RCU_CFG0_PLLSEL | RCU_CFG0_PREDV0);
    RCU_CFG0 |= (RCU_PLLSRC_HXTAL | RCU_CFG0_PREDV0);
    RCU_CFG0 &= ~(RCU_CFG0_PLLMF | RCU_CFG0_PLLMF_4);
    RCU_CFG0 |= RCU_PLL_MUL9;

    RCU_CTL |= RCU_CTL_PLLEN;
    while (0U == (RCU_CTL & RCU_CTL_PLLSTB)) { ; }

    // Переключение SYSCLK на PLL.
    RCU_CFG0 &= ~RCU_CFG0_SCS;
    RCU_CFG0 |= RCU_CKSYSSRC_PLL;
    while (RCU_SCSS_PLL != (RCU_CFG0 & RCU_CFG0_SCSS)) { ; }
}

// ---------------------------------- GPIO ------------------------------------
// LED SYS: PC12. CAN0: PA11 (RX), PA12 (TX). SPI0 к FPGA (PA4..PA7)
// настраивается отдельно в fpga_spi_init().
void GPIO_Configuration(void)
{
    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_GPIOC);
    rcu_periph_clock_enable(RCU_AF);

    // Освободить SWJ-пины под GPIO (JTAG отключён, SWD остаётся).
    gpio_pin_remap_config(GPIO_SWJ_SWDPENABLE_REMAP, ENABLE);

    gpio_init(GPIOC, GPIO_MODE_OUT_PP, GPIO_OSPEED_2MHZ, GPIO_PIN_12);  // LED

    gpio_init(GPIOA, GPIO_MODE_IPU, GPIO_OSPEED_50MHZ, GPIO_PIN_11); // CAN0_RX
    gpio_init(GPIOA, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_12); // CAN0_TX
}

// ----------------------------------- CAN ------------------------------------
// CAN0, 125 кбит/с, режим только передача (кадры статуса FPGA).
void CAN_Configuration(void)
{
    can_parameter_struct can_parameter;

    rcu_periph_clock_enable(RCU_CAN0);

    can_struct_para_init(CAN_INIT_STRUCT, &can_parameter);
    can_deinit(CAN0);

    can_parameter.time_triggered = DISABLE;
    can_parameter.auto_bus_off_recovery = DISABLE;
    can_parameter.auto_wake_up = DISABLE;
    can_parameter.no_auto_retrans = ENABLE;
    can_parameter.rec_fifo_overwrite = DISABLE;
    can_parameter.trans_fifo_order = DISABLE;
    can_parameter.working_mode = CAN_NORMAL_MODE;
    // 125 кбит/с при APB1 = 18 МГц: 16 * (1 + 4 + 4) TQ
    can_parameter.resync_jump_width = CAN_BT_SJW_1TQ;
    can_parameter.time_segment_1 = CAN_BT_BS1_13TQ;
    can_parameter.time_segment_2 = CAN_BT_BS2_2TQ;
    can_parameter.prescaler = 18;
    can_init(CAN0, &can_parameter);
}
