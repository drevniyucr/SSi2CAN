module SPI_SLAVE(
    input  logic clk,
    input  logic rst,

    input  logic spi_sck,
    input  logic spi_mosi,
    input  logic spi_nss,
    output logic spi_miso,

    output logic test_led
);

    // ============================================================
    // RX FIFO interface
    // ============================================================
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_ready;

    logic [7:0] fifo_rx_out;
    logic       fifo_rx_valid;
    logic       fifo_rx_ready;

    // ============================================================
    // TX FIFO interface
    // ============================================================
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;

    logic [7:0] fifo_tx_out;
    logic       fifo_tx_valid;
    logic       fifo_tx_ready;

    // ============================================================
    // FSM
    // ============================================================
    typedef enum logic [2:0] {
        CMD,
        ADDR,
        WRITE,
        READ,
        DUMMY
    } state_t;

    state_t state;

    logic [7:0] cmd, addr;
    logic [7:0] regfile [0:3];


    // ============================================================
    // RX FIFO
    // ============================================================
    FIFO #(
        .DATA_W(8),
        .ADDR_W(4)
    ) rx_fifo_inst (
        .wr_clk(~spi_sck),
        .rd_clk(clk),
        .rst(rst),

        .in_data(rx_data),
        .in_valid(rx_valid),
        .in_ready(rx_ready),

        .out_data(fifo_rx_out),
        .out_valid(fifo_rx_valid),
        .out_ready(fifo_rx_ready),
        .test_led()
    );

    // ============================================================
    // TX FIFO
    // ============================================================
    FIFO #(
        .DATA_W(8),
        .ADDR_W(4)
    ) tx_fifo_inst (
        .wr_clk(clk),
        .rd_clk(spi_sck),
        .rst(rst),

        .in_data(tx_data),
        .in_valid(tx_valid),
        .in_ready(tx_ready),

        .out_data(fifo_tx_out),
        .out_valid(fifo_tx_valid),
        .out_ready(fifo_tx_ready),
         .test_led()
    );

    // ============================================================
    // SPI PHY
    // ============================================================
    SPI_RX_PHY rxphy (
        .spi_sck(spi_sck),
        .rst(rst),
        .spi_mosi(spi_mosi),
        .spi_nss(spi_nss),

        .data(rx_data),
        .valid(rx_valid),
        .ready(rx_ready),
        .test_led()
    );

    SPI_TX_PHY txphy (
        .spi_sck(spi_sck),
        .rst(rst),
        .spi_miso(spi_miso),
        .spi_nss(spi_nss),

        .tx_data(fifo_tx_out),     
        .tx_valid(fifo_tx_valid),
        .tx_ready(fifo_tx_ready),
        .busy(),
        .underrun(),
        .test_led(test_led)
    );

    assign fifo_rx_ready = 1'b1;   // always ready (FIFO handles backpressure)
    // ============================================================
    // FSM (SYSTEM CLOCK DOMAIN)
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            state         <= CMD;
            cmd           <= 8'h00;
            addr          <= 8'h00;
            
            tx_data       <= 8'h00;
            tx_valid      <= 1'b0;

            regfile[0] <= 8'h00;
            regfile[1] <= 8'h00;
            regfile[2] <= 8'h00;
            regfile[3] <= 8'h00;

        end else begin
            tx_valid <= 1'b0;

            case (state)
                CMD: begin
                    if (fifo_rx_valid) begin
                      //  test_led <= ~test_led;
                        cmd <= fifo_rx_out;
                        state <= ADDR;
                    end
                end

                ADDR: begin
                    if (fifo_rx_valid) begin
                        addr <= fifo_rx_out;
                        if      (cmd == 8'h01)begin 
                            state <= WRITE;
                        end else if (cmd == 8'h02) begin
                            state <= READ;
                           //  test_led <= ~test_led;
                        end else 
                            state <= CMD;
                    end
                end

                WRITE: begin
                    if (fifo_rx_valid) begin
                        regfile[3] <= fifo_rx_out;
                        state <= CMD;
                    end
                end

                READ: begin
                    if (tx_ready) begin
                        tx_data <= regfile[3];
                        tx_valid <= 1'b1;
                        state <= DUMMY;
                    end
                end
                DUMMY: begin
                    if (fifo_rx_valid) begin
                        state <= CMD;
                    end
                end

                default: state <= CMD;
            endcase
        end
    end

endmodule