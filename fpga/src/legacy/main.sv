module TOP(
    input logic CLK,
    input logic RST,

    output logic [7:0] EN_CLK,

    input logic [7:0] EN_DATA,
  
    output logic [7:0] EN_STATUS_LED,
    
    input  logic SPI_SCK,
    output logic SPI_MISO,
    input  logic SPI_MOSI,
    input  logic SPI_NSS//output
);

logic [7:0] CLK_BUFF;

logic [255:0] BUFF_NOCRC;
logic [287:0] BUFF_CRC;

logic CRC_START;
logic CRC_DONE;

logic SSI_START;
logic SSI_DONE;

logic SPI_START;
logic SPI_DONE;

logic clk_main;
logic clk_spi;
logic pll_lock;

assign clk_spi = clk_main & pll_lock;

SPI_SLAVE spi_slave_inst (
    .clk(clk_spi),
    .rst(RST),
    .spi_sck(SPI_SCK),
    .spi_miso(SPI_MISO),
    .spi_mosi(SPI_MOSI),
    .spi_nss(SPI_NSS),
    .test_led(EN_STATUS_LED[6])
);

Gowin_rPLL PLL_inst(
    .clkout(clk_main), //output clkout
    .lock(pll_lock), //output lock
    .clkin(CLK) //input clkin
    );


// CRC32 crc32_inst (
//     .clk(CLK),
//     .RST(RST),
//     .BUFF_NOCRC(BUFF_NOCRC),
//     .BUFF_CRC(BUFF_CRC),
//     .CRC_START(CRC_START),
//     .CRC_DONE(CRC_DONE)
// );

// SSI ssi_inst (
//     .CLK(CLK),
//     .EN1_CLK(EN1_CLK),
//     .EN2_CLK(EN2_CLK),
//     .EN3_CLK(EN3_CLK),
//     .EN4_CLK(EN4_CLK),
//     .EN5_CLK(EN5_CLK),
//     .EN6_CLK(EN6_CLK),
//     .EN7_CLK(EN7_CLK),
//     .EN8_CLK(EN8_CLK),
//     .EN1_DATA(EN1_DATA),
//     .EN2_DATA(EN2_DATA),
//     .EN3_DATA(EN3_DATA),
//     .EN4_DATA(EN4_DATA),
//     .EN5_DATA(EN5_DATA),
//     .EN6_DATA(EN6_DATA),
//     .EN7_DATA(EN7_DATA),
//     .EN8_DATA(EN8_DATA)
// );

// LED_Controller led_controller_inst (
//     .CLK(CLK),
//     .EN_STS_LED1(EN_STS_LED1),
//     .EN_STS_LED2(EN_STS_LED2),
//     .EN_STS_LED3(EN_STS_LED3),
//     .EN_STS_LED4(EN_STS_LED4),
//     .EN_STS_LED5(EN_STS_LED5),
//     .EN_STS_LED6(EN_STS_LED6),
//     .EN_STS_LED7(EN_STS_LED7),
//     .EN_STS_LED8(EN_STS_LED8)
// );

endmodule
