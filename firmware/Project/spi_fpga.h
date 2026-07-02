// =============================================================================
// spi_fpga.h — драйвер SPI-мастера GD32F103 для моста encoder_hub (FPGA Gowin)
//
// FPGA = SPI slave (Mode 0, MSB-first), GD32 = SPI master.
// Используется SPI0 + программный NSS на GPIO (полный контроль кадра CS).
//
// Распиновка взята из схемы SRL-8SSI-CAN-MAIN-V1.0 и encoder_hub.cst (Gowin):
//   Линия      Пин GD32      Пин FPGA            Назначение
//   ---------  ------------  -----------------   ---------------------------
//   NSS  (CS)  PA4  (GPIO)   72 (spi_nss)        программный, активный 0
//   SCK        PA5  (AF_PP)  71 (spi_sck)        тактирование
//   MISO       PA6  (IN_FLT) 53 (spi_miso)       данные FPGA -> MCU
//   MOSI       PA7  (AF_PP)  52 (spi_mosi)       команды  MCU -> FPGA
//
// Тактовая FPGA-slave синхронизирует SCK/MOSI через 2 триггера в своём
// домене (clk_pll). Поэтому SPI-частота должна быть много ниже clk FPGA.
// При SYSCLK=36 МГц SPI0 на PCLK2=36 МГц, делитель /256 => ~140 кГц — безопасно.
//
// Сброс FPGA: на плате SRL-8SSI-CAN линия rst заведена на ВНЕШНЮЮ КНОПКУ, а не
// на GPIO GD32 — поэтому MCU сбросом не управляет (FPGA_RST_USE_GPIO=0).
// Готовность моста определяем опросом NOP (== 0x55) через fpga_wait_ready().
// FPGA_RST_USE_GPIO=1 оставлен на случай переноса на плату, где rst на GPIO.
// =============================================================================
#pragma once

#include "gd32f10x.h"
#include <stdint.h>

// ---- Команды протокола (см. encoder_hub README) ----
#define FPGA_CMD_NOP            0x00u   // ответ 0x55
#define FPGA_CMD_READ_ENC(n)    (0x10u + (n))  // 4 байта позиции + CRC8
#define FPGA_CMD_READ_RAW(n)    (0x20u + (n))  // 4 байта сырых + CRC8
#define FPGA_CMD_WRITE_CFG      0xA0u   // + gray_mask + flags + 0x00 -> ACK 0xAA
#define FPGA_CMD_TRIGGER_POLL   0xB0u   // ответ 0x00 (ok) / 0x01 (busy)
#define FPGA_CMD_READ_STATUS    0xC0u   // status-байт
#define FPGA_CMD_READ_FAULT     0xD0u   // маска обрыва
#define FPGA_CMD_READ_ERROR     0xD1u   // маска ошибок
#define FPGA_CMD_READ_VALID     0xD2u   // маска valid
#define FPGA_CMD_READ_ALL_POS   0xE0u   // N*(4+CRC)  — см. примечание о баге wrap
#define FPGA_CMD_READ_ALL_RAW   0xE1u   // N*(4+CRC)

#define FPGA_RESP_NOP           0x55u
#define FPGA_RESP_CFG_ACK       0xAAu
#define FPGA_RESP_UNKNOWN       0xEEu

// status-байт:
//   [2:0] = NUM_ENCODERS-1, [3] busy, [4] any_valid,
//   [5] any_fault, [6] any_error, [7] auto_poll
#define FPGA_STATUS_NENC(s)     (((s) & 0x07u) + 1u)
#define FPGA_STATUS_BUSY        0x08u
#define FPGA_STATUS_ANY_VALID   0x10u
#define FPGA_STATUS_ANY_FAULT   0x20u
#define FPGA_STATUS_ANY_ERROR   0x40u
#define FPGA_STATUS_AUTO_POLL   0x80u

// ---- Управление сбросом FPGA ----
// 0 — rst FPGA на внешней кнопке (плата SRL-8SSI-CAN): MCU им не управляет,
//     fpga_reset_release() — пустышка, готовность ловим опросом NOP.
// 1 — только для других плат, где rst заведён на GPIO: укажите порт/пин ниже.
#ifndef FPGA_RST_USE_GPIO
#define FPGA_RST_USE_GPIO   0
#endif
#define FPGA_RST_PORT       GPIOB
#define FPGA_RST_PIN        GPIO_PIN_0    // используется только при FPGA_RST_USE_GPIO=1

void     fpga_spi_init(void);

// Снять сброс FPGA (rst=0). На SRL-8SSI-CAN (rst на кнопке) — пустышка.
void     fpga_reset_release(void);

// Дождаться готовности FPGA: опрос NOP до ответа 0x55 либо до тайм-аута
// (timeout_iter — число попыток). Возвращает 1, если FPGA ответила корректно.
int      fpga_wait_ready(uint32_t timeout_iter);

// Низкоуровневый обмен одним байтом при уже опущенном NSS.
uint8_t  fpga_spi_xfer(uint8_t tx);

// Управление CS.
void     fpga_cs_low(void);
void     fpga_cs_high(void);

// CRC8 (poly 0x07, init 0x00, без рефлексии) — совпадает с calc_crc8 в FPGA.
uint8_t  fpga_crc8(const uint8_t* data, uint32_t len);

// ---- Высокоуровневые операции ----

// Одно-байтовая команда -> одно-байтовый ответ.
uint8_t  fpga_cmd_read_u8(uint8_t cmd);

// Прочитать позицию энкодера n (0..7): out_pos = 32-бит, возвращает 1 при OK CRC.
int      fpga_read_encoder(uint8_t n, uint32_t* out_pos);
int      fpga_read_raw(uint8_t n, uint32_t* out_raw);

// Записать конфигурацию: gray_mask (бит N=1 -> канал N декодируется из Gray),
// auto_poll (0/1). Возвращает 1, если FPGA вернула ACK 0xAA.
int      fpga_write_cfg(uint8_t gray_mask, uint8_t auto_poll);

// Прочитать все каналы одной транзакцией: cmd = FPGA_CMD_READ_ALL_POS / _RAW.
// out[i] и crc_ok[i] заполняются для i=0..count-1. Возвращает число каналов с OK CRC.
int      fpga_read_all(uint8_t cmd, uint32_t* out, uint8_t* crc_ok, int count);

// Запустить опрос. Возвращает 0 если принято, 1 если FPGA была занята.
uint8_t  fpga_trigger_poll(void);


