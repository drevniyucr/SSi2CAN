module SPI_RX_PHY(
    input  logic spi_sck,
    input  logic rst,
    input  logic spi_mosi,
    input  logic spi_nss,

    output logic [7:0] data,
    output logic       valid,
    input  logic       ready,
    output logic test_led
);

    logic [7:0] shift;
    logic [2:0] bit_cnt;
    logic [7:0] data_buff;

    assign data = data_buff;

always_ff @(posedge spi_sck or posedge spi_nss or posedge rst) begin
    
    if (spi_nss || rst) begin
        bit_cnt  <= 1'b0;
        valid    <= 1'b0;
        shift    <= 1'b0;
        data_buff  <= 1'b0;
   
    end else begin

            shift <= {shift[6:0], spi_mosi}; 

            if (bit_cnt == 3'd7) begin
                data_buff <= {shift[6:0], spi_mosi};
                bit_cnt <= 1'b0;
                valid <= 1'b1;
             //   test_led <= ~test_led;

            end else begin
                bit_cnt <= bit_cnt + 1'b1;
                valid <= 1'b0;
            end
        end
    end


endmodule


