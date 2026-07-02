// =============================================================================
// spi_fpga.c — реализация SPI-мастера для моста encoder_hub
// =============================================================================
#include "spi_fpga.h"
#include "gd32f10x_gpio.h"
#include "gd32f10x_spi.h"
#include "gd32f10x_rcu.h"

// FPGA подключена к SPI0 на PA4..PA7 (см. схему SRL-8SSI-CAN-MAIN-V1.0).
#define FPGA_SPI            SPI0
#define FPGA_SPI_PORT       GPIOA
#define FPGA_PIN_NSS        GPIO_PIN_4
#define FPGA_PIN_SCK        GPIO_PIN_5
#define FPGA_PIN_MISO       GPIO_PIN_6
#define FPGA_PIN_MOSI       GPIO_PIN_7

// --- грубая задержка (несколько мкс) для гарантии setup/hold у slave ---
static void fpga_delay(volatile uint32_t n)
{
    while (n--) { __NOP(); }
}

void fpga_spi_init(void)
{
    spi_parameter_struct spi;

    rcu_periph_clock_enable(RCU_GPIOA);
    rcu_periph_clock_enable(RCU_SPI0);
    rcu_periph_clock_enable(RCU_AF);

    // SCK (PA5) и MOSI (PA7) — альтернативная функция push-pull
    gpio_init(FPGA_SPI_PORT, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ,
        FPGA_PIN_SCK | FPGA_PIN_MOSI);
    // MISO (PA6) — вход
    gpio_init(FPGA_SPI_PORT, GPIO_MODE_IN_FLOATING, GPIO_OSPEED_50MHZ,
        FPGA_PIN_MISO);
    // NSS (PA4) — программный выход push-pull, в покое 1 (CS неактивен)
    gpio_init(FPGA_SPI_PORT, GPIO_MODE_OUT_PP, GPIO_OSPEED_50MHZ,
        FPGA_PIN_NSS);
    gpio_bit_set(FPGA_SPI_PORT, FPGA_PIN_NSS);

    spi_i2s_deinit(FPGA_SPI);
    spi_struct_para_init(&spi);
    spi.device_mode = SPI_MASTER;
    spi.trans_mode = SPI_TRANSMODE_FULLDUPLEX;
    spi.frame_size = SPI_FRAMESIZE_8BIT;
    spi.nss = SPI_NSS_SOFT;       // CS дёргаем сами по GPIO
    spi.endian = SPI_ENDIAN_MSB;
    spi.clock_polarity_phase = SPI_CK_PL_LOW_PH_1EDGE;  // Mode 0
    spi.prescale = SPI_PSC_256;        // SPI0: PCLK2/256 ~ 140 кГц
    spi_init(FPGA_SPI, &spi);

    // SWNSS=1 внутренне, чтобы master не сбрасывался в slave при NSS soft
    spi_nss_internal_high(FPGA_SPI);
    spi_enable(FPGA_SPI);

#if FPGA_RST_USE_GPIO
    // rst FPGA на GPIO: настроить выход PP, по умолчанию держать в сбросе (1)
    rcu_periph_clock_enable(RCU_GPIOB);
    gpio_init(FPGA_RST_PORT, GPIO_MODE_OUT_PP, GPIO_OSPEED_2MHZ, FPGA_RST_PIN);
    gpio_bit_set(FPGA_RST_PORT, FPGA_RST_PIN);
#endif
}

void fpga_reset_release(void)
{
#if FPGA_RST_USE_GPIO
    gpio_bit_reset(FPGA_RST_PORT, FPGA_RST_PIN);  // rst=0 — снять сброс
    fpga_delay(2000);                             // дать PLL захватиться
#endif
}

int fpga_wait_ready(uint32_t timeout_iter)
{
    uint32_t i;
    for (i = 0; i < timeout_iter; i++) {
        if (fpga_cmd_read_u8(FPGA_CMD_NOP) == FPGA_RESP_NOP) return 1;
        fpga_delay(200);
    }
    return 0;
}

uint8_t fpga_spi_xfer(uint8_t tx)
{
    while (RESET == spi_i2s_flag_get(FPGA_SPI, SPI_FLAG_TBE)) {}
    spi_i2s_data_transmit(FPGA_SPI, tx);
    while (RESET == spi_i2s_flag_get(FPGA_SPI, SPI_FLAG_RBNE)) {}
    return (uint8_t)spi_i2s_data_receive(FPGA_SPI);
}

void fpga_cs_low(void)
{
    gpio_bit_reset(FPGA_SPI_PORT, FPGA_PIN_NSS);
    fpga_delay(50);   // дать slave увидеть фронт NSS (синхронизация в clk FPGA)
}

void fpga_cs_high(void)
{
    // дождаться окончания сдвига перед снятием CS
    while (RESET != spi_i2s_flag_get(FPGA_SPI, SPI_FLAG_TRANS)) {}
    fpga_delay(50);
    gpio_bit_set(FPGA_SPI_PORT, FPGA_PIN_NSS);
    fpga_delay(50);
}

uint8_t fpga_crc8(const uint8_t* data, uint32_t len)
{
    uint8_t crc = 0x00u;
    uint32_t i;
    int b;
    for (i = 0; i < len; i++) {
        crc ^= data[i];
        for (b = 0; b < 8; b++) {
            if (crc & 0x80u) crc = (uint8_t)((crc << 1) ^ 0x07u);
            else             crc = (uint8_t)(crc << 1);
        }
    }
    return crc;
}

uint8_t fpga_cmd_read_u8(uint8_t cmd)
{
    uint8_t resp;
    fpga_cs_low();
    (void)fpga_spi_xfer(cmd);   // байт команды (одновременный rx — мусор)
    resp = fpga_spi_xfer(0x00); // ответ приходит в следующем байте
    fpga_cs_high();
    return resp;
}

// общий помощник: команда чтения 32-бит слова (READ_ENC / READ_RAW)
static int fpga_read_word(uint8_t cmd, uint32_t* out)
{
    uint8_t buf[4];
    uint8_t crc_rx, crc_calc;
    int i;

    fpga_cs_low();
    (void)fpga_spi_xfer(cmd);
    for (i = 0; i < 4; i++)
        buf[i] = fpga_spi_xfer(0x00);
    crc_rx = fpga_spi_xfer(0x00);
    fpga_cs_high();

    crc_calc = fpga_crc8(buf, 4);
    *out = ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) |
        ((uint32_t)buf[2] << 8) | (uint32_t)buf[3];
    return (crc_rx == crc_calc) ? 1 : 0;
}

int fpga_read_encoder(uint8_t n, uint32_t* out_pos)
{
    return fpga_read_word(FPGA_CMD_READ_ENC(n), out_pos);
}

int fpga_read_raw(uint8_t n, uint32_t* out_raw)
{
    return fpga_read_word(FPGA_CMD_READ_RAW(n), out_raw);
}

int fpga_write_cfg(uint8_t gray_mask, uint8_t auto_poll)
{
    uint8_t ack;
    fpga_cs_low();
    (void)fpga_spi_xfer(FPGA_CMD_WRITE_CFG);
    (void)fpga_spi_xfer(gray_mask);
    (void)fpga_spi_xfer(auto_poll ? 0x01u : 0x00u);
    ack = fpga_spi_xfer(0x00);   // ACK 0xAA в 4-м байте
    fpga_cs_high();
    return (ack == FPGA_RESP_CFG_ACK) ? 1 : 0;
}

uint8_t fpga_trigger_poll(void)
{
    return fpga_cmd_read_u8(FPGA_CMD_TRIGGER_POLL);
}

int fpga_read_all(uint8_t cmd, uint32_t* out, uint8_t* crc_ok, int count)
{
    uint8_t buf[4];
    uint8_t crc_rx;
    int e, i, ok = 0;

    fpga_cs_low();
    (void)fpga_spi_xfer(cmd);
    for (e = 0; e < count; e++) {
        for (i = 0; i < 4; i++)
            buf[i] = fpga_spi_xfer(0x00);
        crc_rx = fpga_spi_xfer(0x00);

        out[e] = ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) |
            ((uint32_t)buf[2] << 8) | (uint32_t)buf[3];
        crc_ok[e] = (crc_rx == fpga_crc8(buf, 4)) ? 1 : 0;
        if (crc_ok[e]) ok++;
    }
    fpga_cs_high();
    return ok;
}
