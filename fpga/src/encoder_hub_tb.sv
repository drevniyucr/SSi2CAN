// =============================================================================
// encoder_hub_tb — testbench для encoder_hub_top
// =============================================================================
`timescale 1ns/1ps

module encoder_hub_tb;

    localparam int NUM_ENCODERS = 2;
    localparam int DATA_BITS    = 8;
    localparam int CLK_DIV      = 4;
    localparam int T_IDLE       = 20;
    localparam int DISC_WAIT    = 32;  // пауза модели обрыва перед проверкой

    logic clk;
    logic rst;

    logic [NUM_ENCODERS-1:0] ssi_data;
    logic [NUM_ENCODERS-1:0] ssi_clk;

    logic spi_nss;
    logic spi_sck;
    logic spi_mosi;
    logic spi_miso;
    logic test_out;

    logic [DATA_BITS-1:0] enc_model [NUM_ENCODERS];
    logic [4:0]           enc_bit   [NUM_ENCODERS];
    logic [7:0]           idle_hi   [NUM_ENCODERS];
    logic [NUM_ENCODERS-1:0] ssi_clk_d;
    logic                 enc1_disconnected;

    encoder_hub_top #(
        .NUM_ENCODERS (NUM_ENCODERS),
        .DATA_BITS    (DATA_BITS),
        .CLK_DIV      (CLK_DIV),
        .T_IDLE       (T_IDLE),
        .AUTO_PERIOD  (1000),
        .USE_PLL      (0)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .ssi_data (ssi_data),
        .ssi_clk  (ssi_clk),
        .enc_led  (),
        .spi_nss  (spi_nss),
        .spi_sck  (spi_sck),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .test_out (test_out)
    );

    initial begin
        clk = 0;
        forever #1 clk = ~clk;
    end

    // Модель энкодера: MSB первым, бит меняется по спаду / читается по фронту
    // ssi_clk. enc_bit продвигается по нарастающему фронту, сбрасывается в начале
    // кадра (по межкадровому простою — clk долго высокий).
    always_comb begin
        for (int e = 0; e < NUM_ENCODERS; e++) begin
            if (e == 1 && enc1_disconnected)
                ssi_data[e] = 1'b1;                          // обрыв: линия в 1
            else if (enc_bit[e] < DATA_BITS)
                ssi_data[e] = enc_model[e][DATA_BITS - 1 - enc_bit[e]];
            else
                ssi_data[e] = 1'b0;                          // монофлоп после кадра
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int e = 0; e < NUM_ENCODERS; e++) begin
                enc_bit[e] <= 0;
                idle_hi[e] <= 0;
            end
            ssi_clk_d <= '1;
        end else begin
            ssi_clk_d <= ssi_clk;
            for (int e = 0; e < NUM_ENCODERS; e++) begin
                if (ssi_clk[e]) begin
                    if (idle_hi[e] != 8'hFF) idle_hi[e] <= idle_hi[e] + 1'b1;
                end else
                    idle_hi[e] <= 0;

                if (idle_hi[e] > CLK_DIV)                    // начало нового кадра
                    enc_bit[e] <= 0;
                else if (~ssi_clk_d[e] & ssi_clk[e] & (enc_bit[e] < DATA_BITS))
                    enc_bit[e] <= enc_bit[e] + 1'b1;         // нарастающий фронт
            end
        end
    end

    task automatic spi_byte(input logic [7:0] mosi, output logic [7:0] miso);
        int i;
        miso = 8'h00;
        for (i = 0; i < 8; i++) begin
            repeat (5) @(posedge clk);
            spi_mosi = mosi[7-i];
            repeat (5) @(posedge clk);
            spi_sck = 1'b1;
            repeat (5) @(posedge clk);
            miso[7-i] = spi_miso;
            repeat (5) @(posedge clk);
            spi_sck = 1'b0;
        end
    endtask

    task automatic spi_transfer(input logic [7:0] cmd, input int resp_len);
        logic [7:0] rx;
        int i;
        spi_nss = 1'b0;
        repeat (4) @(posedge clk);
        spi_byte(cmd, rx);
        for (i = 0; i < resp_len; i++) begin
            spi_byte(8'h00, rx);
            $display("SPI cmd=0x%02h RX[%0d] = 0x%02h", cmd, i, rx);
        end
        spi_nss = 1'b1;
        repeat (4) @(posedge clk);
    endtask

    task automatic spi_write_cfg(input logic [7:0] gray_mask, input logic [7:0] flags);
        logic [7:0] rx;
        spi_nss = 1'b0;
        repeat (4) @(posedge clk);
        spi_byte(8'hA0, rx);
        spi_byte(gray_mask, rx);
        spi_byte(flags, rx);
        spi_byte(8'h00, rx);
        $display("CFG ACK = 0x%02h (gray=0x%02h flags=0x%02h)", rx, gray_mask, flags);
        spi_nss = 1'b1;
        repeat (4) @(posedge clk);
    endtask

    initial begin
        $dumpfile("encoder_hub.vcd");
        $dumpvars(0, encoder_hub_tb);

        spi_nss  = 1'b1;
        spi_sck  = 1'b0;
        spi_mosi = 1'b0;
        enc1_disconnected = 1'b0;

        for (int e = 0; e < NUM_ENCODERS; e++) begin
            enc_model[e] = 8'hA5 + e;
            enc_bit[e]   = 0;
        end

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        // --- Нормальный опрос, оба энкодера подключены ---
        spi_transfer(8'hB0, 1);
        repeat (500) @(posedge clk);
        spi_transfer(8'hD2, 1);
        spi_transfer(8'hD1, 1);
        spi_transfer(8'h10, 5);
        spi_transfer(8'h11, 5);
        spi_transfer(8'hE0, NUM_ENCODERS * 5);
        spi_transfer(8'hE1, NUM_ENCODERS * 5);

        // --- Энкодер 1 отключён: линия DATA всегда 1 ---
        enc1_disconnected = 1'b1;
        repeat (DISC_WAIT + 10) @(posedge clk);
        spi_transfer(8'hD0, 1);

        spi_transfer(8'hB0, 1);
        repeat (500) @(posedge clk);
        spi_transfer(8'hD1, 1);
        spi_transfer(8'hD2, 1);
        spi_transfer(8'h11, 5);

        spi_write_cfg(8'h00, 8'h00);
        enc1_disconnected = 1'b0;

        $display("ENCODER HUB TEST PASSED");
        repeat (10) @(posedge clk);
        $finish;
    end

endmodule
