// =============================================================================
// fpga_test.c — последовательность тестов протокола encoder_hub
//
// Прогоняет все команды SPI-протокола и фиксирует результат в g_fpga:
// NOP, STATUS, WRITE CFG, TRIGGER POLL, маски FAULT/ERROR/VALID, позиции и
// сырые данные по каналам (0x10+N / 0x20+N) с проверкой CRC8, чтение всех
// каналов одной транзакцией (0xE0), неизвестная команда.
// =============================================================================
#include "fpga_test.h"
#include "spi_fpga.h"

volatile fpga_test_result_t g_fpga;

static void check(int cond)
{
    g_fpga.checks_total++;
    if (!cond) g_fpga.checks_failed++;
}

static void busy_wait_ms(uint32_t ms)
{
    // ~ при SYSCLK 36 МГц; точность некритична — ждём завершения опроса SSI
    volatile uint32_t n = ms * 6000u;
    while (n--) { __NOP(); }
}

uint16_t fpga_test_run(void)
{
    uint8_t  v;
    uint32_t pos;
    int      i, n;

    g_fpga.checks_total  = 0;
    g_fpga.checks_failed = 0;

    fpga_spi_init();
    fpga_reset_release();        // снять сброс (fpga_spi_init мог его взвести)
    fpga_wait_ready(200000);       // дождаться готовности перед проверками

    // 1) NOP -> 0x55 (базовая проверка линии и SPI-режима)
    v = fpga_cmd_read_u8(FPGA_CMD_NOP);
    g_fpga.nop_ok = (v == FPGA_RESP_NOP);
    check(g_fpga.nop_ok);

    // 2) STATUS -> определяем число каналов
    g_fpga.status = fpga_cmd_read_u8(FPGA_CMD_READ_STATUS);
    g_fpga.num_encoders = FPGA_STATUS_NENC(g_fpga.status);
    check(g_fpga.num_encoders >= 1 && g_fpga.num_encoders <= FPGA_TEST_MAX_ENC);
    n = g_fpga.num_encoders;

    // 3) WRITE CFG: все каналы как Gray->Binary, авто-опрос включён -> ACK 0xAA
    g_fpga.cfg_ack_ok = (uint8_t)fpga_write_cfg(0x00, 0);
    check(g_fpga.cfg_ack_ok);

    // 4) TRIGGER POLL + ожидание завершения
    g_fpga.poll_accepted = (fpga_trigger_poll() == 0x00u);
    check(g_fpga.poll_accepted);
    busy_wait_ms(5);                 // дать SSI-кадрам отработать

    // дождаться снятия busy в status (с тайм-аутом)
    for (i = 0; i < 1000; i++) {
        g_fpga.status = fpga_cmd_read_u8(FPGA_CMD_READ_STATUS);
        if (!(g_fpga.status & FPGA_STATUS_BUSY)) break;
    }
    check(!(g_fpga.status & FPGA_STATUS_BUSY));

    // 5) Маски состояния
    g_fpga.fault_mask = fpga_cmd_read_u8(FPGA_CMD_READ_FAULT);
    g_fpga.error_mask = fpga_cmd_read_u8(FPGA_CMD_READ_ERROR);
    g_fpga.valid_mask = fpga_cmd_read_u8(FPGA_CMD_READ_VALID);

    // 6) Позиции и сырые данные по каждому каналу + проверка CRC8
    for (i = 0; i < n; i++) {
        g_fpga.pos_crc_ok[i] = (uint8_t)fpga_read_encoder((uint8_t)i, &pos);
        g_fpga.pos[i] = pos;
        check(g_fpga.pos_crc_ok[i]);

        g_fpga.raw_crc_ok[i] = (uint8_t)fpga_read_raw((uint8_t)i, &pos);
        g_fpga.raw[i] = pos;
        check(g_fpga.raw_crc_ok[i]);
    }

    // 7) Чтение всех каналов одной транзакцией (0xE0) и сверка с поканальным
    {
        uint32_t all[FPGA_TEST_MAX_ENC];
        uint8_t  all_ok[FPGA_TEST_MAX_ENC];
        int ok = fpga_read_all(FPGA_CMD_READ_ALL_POS, all, all_ok, n);
        check(ok == n);                       // все CRC сошлись
        for (i = 0; i < n; i++)
            check(all[i] == g_fpga.pos[i]);   // совпадает с поканальным чтением
    }

    // 8) Неизвестная команда -> 0xEE
    v = fpga_cmd_read_u8(0x77);
    check(v == FPGA_RESP_UNKNOWN);

    // 9) Возврат конфигурации к "сырому" режиму, авто-опрос выкл.
    check(fpga_write_cfg(0x00, 0));

    return g_fpga.checks_failed;
}

void fpga_test_poll_once(void)
{
    int i, n;
    uint32_t pos;

    (void)fpga_trigger_poll();
    busy_wait_ms(3);

    g_fpga.status       = fpga_cmd_read_u8(FPGA_CMD_READ_STATUS);
    g_fpga.num_encoders = FPGA_STATUS_NENC(g_fpga.status);
    g_fpga.error_mask   = fpga_cmd_read_u8(FPGA_CMD_READ_ERROR);

    n = g_fpga.num_encoders;
    for (i = 0; i < n; i++) {
        g_fpga.pos_crc_ok[i] = (uint8_t)fpga_read_encoder((uint8_t)i, &pos);
        g_fpga.pos[i] = pos;
    }
}
