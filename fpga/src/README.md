# Encoder Hub — SSI Master + SPI Slave

FPGA-мост (Gowin GW2AR-18) для параллельного опроса абсолютных SSI-энкодеров и
передачи позиций во внешний MCU (GD32F103) по SPI Mode 0.

## Структура проекта

```text
encoder_hub_top.sv      — верхний уровень (PLL, сброс по lock, связка модулей)
├── encoder_ctrl.sv     — FSM опроса, маски valid/error/fault, регистры позиций
│   └── encoder_channel.sv (×NUM_ENCODERS) — ssi_reader + инлайновый Gray→Binary
│       └── ssi_reader.sv  — приём одного SSI-кадра (мастер SSI)
└── spi_slave.sv        — SPI Mode 0 slave, протокол команд

encoder_hub_tb.sv       — testbench (модель энкодеров + SPI-мастер)
encoder_hub.cst         — ограничения пинов (Gowin)
encoder_hub.sdc         — временные ограничения
```

> Gray→Binary встроен в `encoder_channel` (отдельного `gray_decoder.sv` нет).
> Детекция обрыва встроена в `ssi_reader`/`encoder_ctrl` (отдельного
> `encoder_fault_mon.sv` нет).

## Параметры `encoder_hub_top`

| Параметр | Описание |
|----------|----------|
| `NUM_ENCODERS` | Число каналов SSI (отдельные пары CLK/DATA на канал) |
| `DATA_BITS` | Длина SSI-кадра в битах (обычно 13…25) |
| `CLK_DIV` | Делитель `clk_pll`: F_ssi = F_pll / (2·CLK_DIV) |
| `T_IDLE` | Пауза между SSI-кадрами в тактах `clk_pll` (t_react энкодера) |
| `AUTO_PERIOD` | Период авто-опроса в тактах `clk_pll` (при `cfg_auto_poll=1`) |
| `USE_PLL` | 1 — тактирование от `Gowin_rPLL`; 0 — напрямую от `clk` (симуляция) |

## Тактирование и сброс

- Рабочий клок — `clk_pll` (выход `Gowin_rPLL`).
- Вместо гейтинга клока логика удерживается в сбросе до захвата PLL:
  `rst_int = rst | ~lock_pll`.
- `test_out` (пин 85) = `lock_pll` — индикатор захвата PLL для отладки.
- **`rst` активен по «1»**, а в `encoder_hub.cst` имеет `PULL_MODE=UP`. При включении
  плата висит в сбросе — **MCU обязан подать на `rst` лог. 0**, чтобы мост заработал.

## SSI-протокол приёма

`clk` энкодера в покое высокий. После старта и паузы `T_IDLE` генерируются
`DATA_BITS+1` импульсов; на каждом нарастающем фронте читается бит (**MSB
первым**). Последний (контрольный) фронт проверяет линию: если DATA осталась в
«1» (нет монофлоп-«0» от энкодера) → `error=1` (обрыв / отсутствие энкодера).

## SPI-протокол

Только **первый байт** транзакции (после NSS↓) — команда. Ответ приходит,
начиная со **следующего** байта (slave регистрирует MISO), поэтому после байта
команды MCU шлёт dummy-байты `0x00`. SPI-частота должна быть много ниже `clk_pll`
(slave синхронизирует SCK/MOSI двумя триггерами).

| Команда | Код | Ответ |
|---------|-----|-------|
| NOP | `0x00` | `0x55` |
| READ ENC N | `0x10+N` | 4 байта позиции MSB-first + CRC8 |
| READ RAW N | `0x20+N` | 4 байта сырых + CRC8 |
| WRITE CFG | `0xA0` + gray_mask + flags + `0x00` | `0xAA` |
| TRIGGER POLL | `0xB0` | `0x00` (принято) / `0x01` (busy) |
| READ STATUS | `0xC0` | status-байт |
| READ FAULT | `0xD0` | маска fault |
| READ ERROR | `0xD1` | маска error последнего опроса |
| READ VALID | `0xD2` | маска valid последнего опроса |
| READ ALL POS | `0xE0` | N×(4 байта + CRC8) — позиции всех каналов |
| READ ALL RAW | `0xE1` | N×(4 байта + CRC8) — сырые данные |
| Unknown | — | `0xEE` |

**Формат слова:** байты `[31:24] [23:16] [15:8] [7:0]`, затем `CRC8` от 32-битного
слова. CRC8: полином `0x07`, init `0x00`, без рефлексии, старший байт первым.

**WRITE CFG:** `gray_mask[7:0]` — бит N=1: канал N конвертируется Gray→Binary
(иначе позиция = сырое значение); `flags[0]` = `auto_poll`.

**status-байт:**

| Бит | Значение |
|-----|----------|
| `[2:0]` | `NUM_ENCODERS-1` |
| `[3]` | busy (идёт опрос) |
| `[4]` | any_valid |
| `[5]` | any_fault |
| `[6]` | any_error |
| `[7]` | auto_poll включён |

## Valid / Error / Fault

- **valid[i]** — последний опрос канала i завершён без ошибки.
- **error[i]** — последний опрос канала i с ошибкой (обрыв / DATA постоянно «1»).
- **fault[i]** — фиксируемая защёлка: взводится при любой ошибке канала и держится
  **до аппаратного сброса** (диагностический латч). `valid`/`error` отражают
  только последний опрос.

## Симуляция (iverilog)

Testbench инстанцирует top с `USE_PLL(0)` — модель `Gowin_rPLL` не нужна.

```bash
iverilog -g2012 -o sim_hub.out \
  ssi_reader.sv encoder_channel.sv encoder_ctrl.sv \
  spi_slave.sv encoder_hub_top.sv encoder_hub_tb.sv
vvp sim_hub.out
```

## Типичный сценарий MCU

1. Подать `rst=0` (снять сброс FPGA), дождаться `test_out=1` (PLL захвачен).
2. `0xB0` — запустить опрос; либо включить `auto_poll` через `0xA0`.
3. `0xC0` / `0xD1` / `0xD2` — проверить busy / error / valid.
4. `0xE0` — прочитать все позиции одной транзакцией (с проверкой CRC8).
5. `0xA0`, `gray_mask`, `flags`, `0x00` — настроить Gray-каналы и авто-опрос.

Пример прошивки GD32 (использует этот мост) — в `../../firmware/`.
