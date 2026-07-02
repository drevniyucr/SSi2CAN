// =============================================================================
// encoder_hub_top — верхний уровень моста SSI-энкодеров ↔ SPI Slave
//
// FPGA — мастер для энкодеров (SSI, параллельный опрос всех каналов) и
// slave для внешнего MCU (SPI Mode 0). Состав: encoder_ctrl + spi_slave.
//
// Параметры:
//   NUM_ENCODERS — число каналов SSI (отдельные пары CLK/DATA на канал)
//   DATA_BITS    — длина SSI-кадра в битах (обычно 13…25)
//   CLK_DIV      — делитель clk_pll: F_ssi = F_pll / (2*CLK_DIV)
//   T_IDLE       — пауза в тактах clk_pll между SSI-кадрами (t_react энкодера)
//   AUTO_PERIOD  — период авто-опроса в тактах clk_pll (при cfg_auto_poll=1)
//   USE_PLL      — 1: тактирование от Gowin_rPLL; 0: напрямую от clk (для симуляции)
// =============================================================================
module encoder_hub_top #(
    parameter int NUM_ENCODERS = 8,
    parameter int DATA_BITS    = 24,
    parameter int CLK_DIV      = 300,
    parameter int T_IDLE       = 2000,
    parameter int AUTO_PERIOD  = 1300000,
    parameter bit USE_PLL      = 1
) (
    input  logic clk,
    input  logic rst,

    // SSI: DATA — вход от энкодера, CLK — выход к энкодеру (FPGA — мастер SSI)
    input  logic [NUM_ENCODERS-1:0] ssi_data,
    output logic [NUM_ENCODERS-1:0] ssi_clk,
    output logic [NUM_ENCODERS-1:0] enc_led,
    // SPI Mode 0, slave: NSS active low
    input  logic spi_nss,
    input  logic spi_sck,
    input  logic spi_mosi,
    output logic spi_miso,

    output logic test_out
);

    // Сигналы связи между SSI-контроллером и SPI-интерфейсом
    logic        poll_req;
    logic        poll_busy;
    logic [7:0]  cfg_gray_mask;   // bit N: канал N в Gray → Binary
    logic        cfg_auto_poll;   // 1 = периодический опрос без команды от MCU
    logic [7:0]  status;

    logic [NUM_ENCODERS*32-1:0] enc_pos_flat;
    logic [NUM_ENCODERS*32-1:0] enc_raw_flat;
    logic [NUM_ENCODERS-1:0]    enc_fault_mask;
    logic [NUM_ENCODERS-1:0]    enc_error_mask;
    logic [NUM_ENCODERS-1:0]    enc_valid_mask;

    // Тактирование: clk_pll — рабочий клок, lock — признак захвата PLL.
    logic clk_pll;
    logic lock_pll;
    logic rst_int;

    generate
        if (USE_PLL) begin : g_pll
            Gowin_rPLL PLLL (
                .clkout (clk_pll),   // output clkout
                .lock   (lock_pll),  // output lock
                .clkin  (clk)        // input  clkin
            );
        end else begin : g_nopll
            // Обход PLL для симуляции
            assign clk_pll  = clk;
            assign lock_pll = 1'b1;
        end
    endgenerate

    // Логика удерживается в сбросе, пока PLL не захватился (вместо гейтинга клока)
    assign rst_int  = rst | ~lock_pll;
    assign test_out = lock_pll;

    encoder_ctrl #(
        .NUM_ENCODERS (NUM_ENCODERS),
        .DATA_BITS    (DATA_BITS),
        .CLK_DIV      (CLK_DIV),
        .T_IDLE       (T_IDLE),
        .AUTO_PERIOD  (AUTO_PERIOD)
    ) u_enc (
        .clk            (clk_pll),
        .rst            (rst_int),
        .ssi_data       (ssi_data),
        .ssi_clk        (ssi_clk),
        .poll_req       (poll_req),
        .poll_busy      (poll_busy),
        .cfg_gray_mask  (cfg_gray_mask),
        .cfg_auto_poll  (cfg_auto_poll),
        .enc_error_mask (enc_error_mask),
        .enc_valid_mask (enc_valid_mask),
        .enc_fault_mask (enc_fault_mask),
        .enc_pos_data   (enc_pos_flat),
        .enc_raw_data   (enc_raw_flat),
        .status         (status),
        .enc_leds       (enc_led)
    );

    spi_slave #(
        .NUM_ENCODERS (NUM_ENCODERS)
    ) u_spi (
        .clk            (clk_pll),
        .rst            (rst_int),
        .spi_nss        (spi_nss),
        .spi_sck        (spi_sck),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),
        .enc_pos_flat   (enc_pos_flat),
        .enc_raw_flat   (enc_raw_flat),
        .enc_fault_mask (enc_fault_mask),
        .enc_error_mask (enc_error_mask),
        .enc_valid_mask (enc_valid_mask),
        .poll_req       (poll_req),
        .poll_busy      (poll_busy),
        .cfg_gray_mask  (cfg_gray_mask),
        .cfg_auto_poll  (cfg_auto_poll),
        .status         (status)
    );

endmodule
