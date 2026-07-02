module spi_tx_phy (
    input  logic        clk,
    input  logic        rst,

    input  logic [7:0]  tx_data,
    input  logic        data_valid,
    output logic        tx_ready,

    input  logic        spi_nss,
    input  logic        spi_sck,
    output logic        spi_miso
);

    logic [7:0] shift_reg;
    logic [7:0] next_reg;
    logic [2:0] bit_cnt;
    logic       have_data;

    // Synchronizers for SPI signals
    logic nss_meta, nss_sync, nss_prev;
    logic sck_meta, sck_sync, sck_prev;

    // Edge detection
    wire nss_rise = (nss_sync && !nss_prev);
    wire nss_fall = (!nss_sync && nss_prev);
    wire sck_fall = (!sck_sync && sck_prev);
    
always_ff @(posedge clk or posedge rst) begin

    if (rst) begin
        shift_reg <= 0;
        next_reg  <= 0;
        bit_cnt   <= 0;
        have_data <= 0;
        spi_miso  <= 0;

        nss_meta <= 0;
        nss_sync <= 0;
        nss_prev <= 0;

        sck_meta <= 0;
        sck_sync <= 0;
        sck_prev <= 0;

        tx_ready <= 0;

    end else begin

        tx_ready <= 0;

        nss_meta <= spi_nss;
        nss_sync <= nss_meta;
        nss_prev <= nss_sync;

        sck_meta <= spi_sck;
        sck_sync <= sck_meta;
        sck_prev <= sck_sync;

        if (nss_rise) begin

            if (!have_data && data_valid) begin
                next_reg  <= tx_data;
                have_data <= 1;
                tx_ready  <= 1;
            end

            spi_miso <= 0;
            shift_reg <= 0;
            bit_cnt <= 0;

        end
        else if (nss_fall) begin

            spi_miso <= next_reg[7];
            shift_reg <= {next_reg[6:0], 1'b0};

            bit_cnt <= 0;

        end
        else if (sck_fall) begin

            if (have_data) begin

                spi_miso <= shift_reg[7];
                shift_reg <= {shift_reg[6:0], 1'b0};

                bit_cnt <= bit_cnt + 1'b1;

                if (bit_cnt == 3'd6) begin
                    have_data <= 0;
                end
            end
        end
    end
end
endmodule