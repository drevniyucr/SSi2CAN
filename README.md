# SRL-8SSI-CAN — программное обеспечение

Прошивки модуля **SRL-8SSI-CAN** — шлюза, который параллельно опрашивает до
8 абсолютных **SSI-энкодеров** и отдаёт их позиции в шину **CAN**.

Репозиторий содержит две связанные части:

| Часть | Каталог | Платформа | Роль |
|-------|---------|-----------|------|
| **Gateware (FPGA)** | [`fpga/`](fpga/) | Gowin GW2AR-18 | Мост `encoder_hub`: SSI-мастер ×8 + SPI-slave |
| **Firmware (MCU)** | [`firmware/`](firmware/) | GD32F103RB (Cortex-M3) | Опрос моста по SPI, трансляция позиций в CAN, самотест, индикация |

## Как это работает

```text
   ┌─────────────┐     SSI ×8     ┌──────────────────────┐   SPI Mode 0     ┌──────────────┐  CAN
   │  Энкодеры   │ ──CLK/DATA──▶ │ FPGA (encoder_hub)    │◀──────────────▶│   GD32F103    │◀─────▶ шина
   │ (абсолютн.) │                │ SSI-мастер + SPI-slv │   позиции/CRC    │  (firmware)   │        (0x40)
   └─────────────┘                └──────────────────────┘                  └──────────────┘
```

1. **FPGA** тактирует все SSI-каналы, принимает кадры (MSB-first), при необходимости
   декодирует Gray→Binary, считает CRC8 и хранит позиции в регистрах.
2. **GD32** — SPI-мастер: командами протокола запускает опрос, читает позиции,
   маски `valid`/`error`/`fault` и статус, проверяет CRC8.
3. Позиции и статус упаковываются в CAN-кадр `SFID = 0x40` и уходят в шину.
4. Светодиод **SYS** показывает итог стартового самотеста (ОК — редкая вспышка,
   ошибка — частое мигание).

Полное описание SPI-протокола, набора команд и формата слов — в
[`fpga/src/README.md`](fpga/src/README.md).

## Структура репозитория

```text
soft/
├── fpga/                       Gowin-проект моста encoder_hub
│   ├── encoder_hub.gprj        файл проекта Gowin EDA
│   └── src/                    исходники (SystemVerilog), constraints, README
│       ├── encoder_hub_top.sv  верхний уровень
│       ├── encoder_ctrl.sv     FSM опроса
│       ├── encoder_channel.sv  канал: SSI-приём + Gray→Binary
│       ├── ssi_reader.sv       приём одного SSI-кадра
│       ├── spi_slave.sv        SPI Mode 0 slave
│       ├── encoder_hub_tb.sv   testbench (iverilog)
│       ├── encoder_hub.cst     ограничения пинов
│       ├── encoder_hub.sdc     временные ограничения
│       ├── gowin_rpll/         IP PLL (Gowin)
│       └── legacy/             ранние эксперименты (не участвуют в сборке)
│
├── firmware/                   Прошивка GD32 (CMSIS-Toolbox / csolution)
│   ├── firmware.csolution.yml  решение (target GD32F103RB, компиляторы)
│   ├── vcpkg-configuration.json версии тулчейна (cmsis-toolbox, cmake, armclang…)
│   └── src/                    исходники прошивки
│       ├── main.c              инициализация, самотест, планировщик задач
│       ├── spi_fpga.c/.h       драйвер SPI-мастера + протокол encoder_hub
│       ├── fpga_test.c/.h      стартовый самотест моста
│       ├── CAN.c/.h            драйвер CAN
│       ├── configuration.c/.h  тактирование, GPIO
│       ├── timer.c/.h          системный таймер
│       ├── rtos_v1.c/.h        кооперативный планировщик задач
│       ├── pin.h               пины (LED SYS = PC12)
│       ├── firmware.cproject.yml состав проекта и компоненты
│       └── RTE/                Run-Time Environment (драйверы GD32 StdPeripherals)
│
├── .vscode/                    рекомендуемые расширения и настройки редактора
└── software.code-workspace     workspace VS Code
```

> Каталоги сборки (`out/`, `tmp/`, `impl/`) и продукты симуляции (`*.vcd`, `*.out`)
> не хранятся в репозитории — см. [`.gitignore`](.gitignore). Они полностью
> воссоздаются тулчейнами.

## Сборка

### FPGA (Gowin EDA)

1. Открыть `fpga/encoder_hub.gprj` в **Gowin EDA**.
2. Synthesize → Place & Route → Program Device.
3. Результаты P&R (в т.ч. битстрим) появятся в игнорируемом `fpga/impl/`.

Симуляция через iverilog (`test_out` = индикатор захвата PLL):

```bash
cd fpga/src
iverilog -g2012 -o sim_hub.out \
  ssi_reader.sv encoder_channel.sv encoder_ctrl.sv \
  spi_slave.sv encoder_hub_top.sv encoder_hub_tb.sv
vvp sim_hub.out
```

### Firmware (CMSIS-Toolbox)

Требуемые версии тулчейна зафиксированы в `firmware/vcpkg-configuration.json`
(CMSIS-Toolbox, CMake, Ninja, Arm Compiler 6). Сборка из VS Code (расширение
**Arm CMSIS Solution**) или из командной строки:

```bash
cd firmware
cbuild firmware.csolution.yml --context firmware.Debug --packs
```

Прошивка (`.hex`/`.axf`) появится в игнорируемом `firmware/out/`.
Загрузка и отладка — через ST-Link (конфигурация в `firmware/.vscode/`).

## Целевое железо

- **MCU:** GD32F103RB (ARM Cortex-M3), SYSCLK 36 МГц.
- **FPGA:** Gowin GW2AR-18C (GW2AR-LV18QN88C8/I7).
- **Интерфейс FPGA↔MCU:** SPI0, ~140 кГц, программный NSS (см. `spi_fpga.h`).
- **Плата:** SRL-8SSI-CAN-MAIN-V1.0 (аппаратная часть — в каталоге `../hard/`).

> ⚠️ Линия `rst` FPGA на плате заведена на внешнюю кнопку, а не на GPIO MCU.
> При включении мост удерживается в сбросе до захвата PLL; MCU ловит готовность
> опросом команды NOP (ответ `0x55`). Подробности — в `firmware/src/spi_fpga.h`.
