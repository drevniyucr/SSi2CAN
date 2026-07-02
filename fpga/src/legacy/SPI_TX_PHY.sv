module SPI_TX_PHY (
    input  logic       spi_sck,
    input  logic       spi_nss,
    input  logic       rst,
    // BYTE STREAM INPUT
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    // SPI OUTPUT
    output logic       spi_miso,
    // STATUS
    output logic       busy,
    output logic       underrun,
    output logic       test_led
);
// ============================================================
// REGISTERS
// ============================================================
logic [7:0] shift_reg;
logic [7:0] next_reg;
logic [3:0] bit_phase;
logic have_next;
// ============================================================
// STATUS
// ============================================================
assign tx_ready = !have_next;
assign busy = !spi_nss;

always_ff @(negedge spi_sck or posedge rst) begin

    if (rst) begin
        shift_reg <= 0;
        next_reg  <= 0;
        have_next <= 0;
        bit_phase <= 0;
        spi_miso  <= 0;
        underrun  <= 0;
   
    end else begin


        if(!underrun) begin
            test_led <= ~test_led;
            spi_miso  <= shift_reg[6];
            shift_reg <= {shift_reg[6:0], 1'b0};
        end

        if (!have_next && tx_valid) begin
            next_reg  <= tx_data;
            have_next <= 1;
        end

        if (bit_phase == 7) begin
            bit_phase <= 0;

            if (have_next) begin
                shift_reg <= (next_reg);
                spi_miso  <= next_reg[7];
                  test_led <= ~test_led;
                have_next <= 0;
                underrun  <= 0;

            end else begin
                shift_reg <= 0;
                spi_miso  <= 0;
                underrun  <= 1;
            end
        end 
        else bit_phase <= bit_phase + 1;
    end
end
endmodule



logic [7:0] shift_reg;
logic [7:0] next_reg;
logic [3:0] bit_cnt;
logic have_data;


logic sck_meta;
logic sck_sync;
logic sck_prev;

logic nss_meta;
logic nss_sync;
logic nss_prev;

assign sck_rise =  sck_sync & ~sck_prev;
assign sck_fall = ~sck_sync &  sck_prev;

assign nss_rise =  nss_sync & ~nss_prev;
assign nss_fall = ~nss_sync &  nss_prev;

always_ff@(posedge clk or posedge rst) begin


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
    end

    tx_ready  <= 0; 

    nss_meta <= spi_nss;
    nss_sync <= nss_meta;
    nss_prev <= nss_sync;

    sck_meta <= spi_sck;
    sck_sync <= sck_meta;
    sck_prev <= sck_sync;

    if (nss_rise) begin
        if (!have_data && data_valid) begin
            next_reg <= tx_data;
            have_data <= 1;
            tx_ready <= 1;
        end
        spi_miso <= 0; // Reset MISO on NSS positive edge (end of transaction)
        shift_reg <= 0;
        bit_cnt <= 0 + 1;

    end else if (nss_fall) begin
        spi_miso <= next_reg[7];
        shift_reg <= {next_reg[6:0], 1'b0}; // Shift left on NSS negative edge (start of transaction)
        bit_cnt <= 0;

    end else if (sck_fall) begin
        if(have_data)begin
            if (bit_cnt == 3'd7) begin
                have_data <= 0; // No more data to send after 8 bits
                spi_miso <= 0; // After 8 bits, set MISO low until next transaction
            end else begin
                spi_miso <= shift_reg[7];
                shift_reg <= {shift_reg[6:0], 1'b0};
                bit_cnt <= bit_cnt + 1;
            end
        end
    end 
end