// =============================================================================
// fpga_test.h — тест всех взаимодействий GD32 <-> FPGA encoder_hub по SPI
// =============================================================================
#pragma once

#include <stdint.h>

#define FPGA_TEST_MAX_ENC   8

typedef struct {
    uint8_t  num_encoders;          // из status-байта
    uint8_t  status;                // последний прочитанный status
    uint8_t  nop_ok;                // NOP вернул 0x55
    uint8_t  cfg_ack_ok;            // WRITE CFG вернул 0xAA
    uint8_t  poll_accepted;         // TRIGGER POLL вернул 0x00
    uint8_t  fault_mask;            // 0xD0
    uint8_t  error_mask;            // 0xD1
    uint8_t  valid_mask;            // 0xD2
    uint32_t pos[FPGA_TEST_MAX_ENC];   // позиции (0x10+N)
    uint32_t raw[FPGA_TEST_MAX_ENC];   // сырые (0x20+N)
    uint8_t  pos_crc_ok[FPGA_TEST_MAX_ENC];
    uint8_t  raw_crc_ok[FPGA_TEST_MAX_ENC];
    uint16_t checks_total;
    uint16_t checks_failed;
} fpga_test_result_t;

extern volatile fpga_test_result_t g_fpga;

// Полный однократный прогон всех команд. Возвращает число проваленных проверок
// (0 = все взаимодействия прошли). Результаты — в g_fpga (удобно смотреть в отладчике).
uint16_t fpga_test_run(void);

// Лёгкий периодический опрос позиций (вызывать из RTOS-таска).
void     fpga_test_poll_once(void);

