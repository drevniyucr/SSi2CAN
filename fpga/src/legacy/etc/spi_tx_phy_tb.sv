`timescale 1ns/1ps

module tb_spi_tx;

    //------------------------------------------------------------
    // DUT signals
    //------------------------------------------------------------
    logic clk;
    logic rst;

    logic spi_sck;
    logic spi_nss;

    logic [7:0] tx_data;
    logic data_valid;
    logic tx_ready;

    logic spi_miso;

    //------------------------------------------------------------
    // DUT instance
    //------------------------------------------------------------
    spi_tx_phy dut (
        .clk(clk),
        .rst(rst),

        .spi_sck(spi_sck),
        .spi_nss(spi_nss),

        .tx_data(tx_data),
        .data_valid(data_valid),
        .tx_ready(tx_ready),

        .spi_miso(spi_miso)
    );

    //------------------------------------------------------------
    // System clock (optional, if used internally)
    //------------------------------------------------------------
   initial begin
    $dumpfile("spi_tx_phy.vcd");
    $dumpvars(0, tb_spi_tx);
     clk = 0;
    forever #1 clk = ~clk;
end

    //------------------------------------------------------------
    // SPI clock (slower)
    //------------------------------------------------------------
    task spi_tick;
    begin
        #50 spi_sck = 0;
        #50 spi_sck = 1;
    end
    endtask

    //------------------------------------------------------------
    // NSS control
    //------------------------------------------------------------
    task nss_low;
    begin
        spi_nss = 0;
    end
    endtask

    task nss_high;
    begin
        spi_nss = 1;
    end
    endtask

    //------------------------------------------------------------
    // Send byte via DUT
    //------------------------------------------------------------
    task automatic send_byte(input logic [7:0] data);
        logic [7:0] expected;
        int i;
    begin
        expected = data;

        @(posedge clk);
        tx_data    = data;
        data_valid = 1;
        @(posedge clk);
        nss_high();
        // wait handshake
        wait (tx_ready == 1);
        @(posedge clk);
        data_valid = 0;
        #20;
        //--------------------------------------------------------
        // start SPI transaction
        //--------------------------------------------------------
        nss_low();
        #20;

        //--------------------------------------------------------
        // shift 8 bits
        //--------------------------------------------------------
        for (i = 0; i < 8; i++) begin

            // falling edge triggers shift
            spi_sck = 1;
            // sample MISO
            if (spi_miso !== expected[7-i]) begin
                $display("ERROR bit %0d exp=%b got=%b",
                         i, expected[7-i], spi_miso);
                $fatal;
            end
            #20;
            spi_sck = 0;
            #20;

        end

       // nss_high();
        #20;
    end
    endtask

    //------------------------------------------------------------
    // main test
    //------------------------------------------------------------
    initial begin

        spi_sck = 0;
        spi_nss = 0;

        tx_data = 0;
        data_valid = 0;

        rst = 1;
        #100;
        rst = 0;

        //--------------------------------------------------------
        // basic test vectors
        //--------------------------------------------------------
        send_byte(8'hA5);
        send_byte(8'h3C);
        send_byte(8'hFF);
        send_byte(8'h00);

        $display("SPI TX TEST PASSED");
        #100;
        $finish;
    end

endmodule