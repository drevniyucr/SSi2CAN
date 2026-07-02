// SPI Mode 0 slave — протокол команд MCU ↔ FPGA
module spi_slave #(
    parameter int NUM_ENCODERS
) (
    input  logic clk,
    input  logic rst,

    input  logic spi_nss,
    input  logic spi_sck,
    input  logic spi_mosi,
    output logic spi_miso,

    input  logic [NUM_ENCODERS*32-1:0] enc_pos_flat,
    input  logic [NUM_ENCODERS*32-1:0] enc_raw_flat,
    input  logic [7:0]                 status,
    input  logic [NUM_ENCODERS-1:0]  enc_fault_mask,
    input  logic [NUM_ENCODERS-1:0]  enc_error_mask,
    input  logic [NUM_ENCODERS-1:0]  enc_valid_mask,

    output logic poll_req,
    input  logic poll_busy,

    output logic [7:0] cfg_gray_mask,
    output logic       cfg_auto_poll
);

    localparam int PAYLOAD_MAX = NUM_ENCODERS * 5;
    localparam int TX_IDX_W    = (PAYLOAD_MAX <= 1) ? 1 : $clog2(PAYLOAD_MAX);

    localparam logic [7:0] CMD_NOP           = 8'h00;
    localparam logic [7:0] CMD_READ_ENC_BASE = 8'h10;
    localparam logic [7:0] CMD_READ_RAW_BASE = 8'h20;
    localparam logic [7:0] CMD_WRITE_CFG     = 8'hA0;
    localparam logic [7:0] CMD_TRIGGER_POLL  = 8'hB0;
    localparam logic [7:0] CMD_READ_STATUS   = 8'hC0;
    localparam logic [7:0] CMD_READ_FAULT    = 8'hD0;
    localparam logic [7:0] CMD_READ_ERROR    = 8'hD1;
    localparam logic [7:0] CMD_READ_VALID    = 8'hD2;
    localparam logic [7:0] CMD_READ_ALL_POS  = 8'hE0;
    localparam logic [7:0] CMD_READ_ALL_RAW  = 8'hE1;

    // --- SPI PHY: синхронизация ---
    logic nss_meta, nss_sync, nss_prev;
    logic sck_meta, sck_sync, sck_prev;
    logic mosi_meta, mosi_sync;

    wire nss_rise =  nss_sync && !nss_prev;
    wire nss_fall = !nss_sync && nss_prev;
    wire sck_rise =  sck_sync && !sck_prev;
    wire sck_fall = !sck_sync && sck_prev;
    wire active   = !nss_sync;

    // --- RX / TX ---
    logic [7:0] rx_shift   = '0;
    logic [2:0] rx_bit_cnt = '0;

    logic [7:0] tx_shift   = '0;
    logic [2:0] tx_bit_cnt = '0;
    logic       tx_pending = '0;

    logic [7:0] tx_buf [0:PAYLOAD_MAX-1];
    logic [TX_IDX_W-1:0] tx_len = '0;
    logic [TX_IDX_W-1:0] tx_idx = '0;

    logic       cmd_taken    = '0; // 1 = байт команды в текущей транзакции уже принят
    logic [1:0] cfg_rx_phase = '0; // 0 = команда, 1..2 = приём данных для команды
   

  function automatic logic [7:0] calc_crc8(input logic [31:0] word);
    logic [7:0] acc;
    int b, i;

    acc = 8'h00;

    for (b = 0; b < 4; b++) begin
        acc ^= word[31 - b*8 -: 8];

        for (i = 0; i < 8; i++) begin
            if (acc[7])
                acc = (acc << 1) ^ 8'h07;
            else
                acc = (acc << 1);
        end
    end

    return acc;
endfunction

    function automatic logic [31:0] get_word(
        input logic [NUM_ENCODERS*32-1:0] flat,
        input int                         idx
    );
        if (idx >= 0 && idx < NUM_ENCODERS)
            return flat[idx*32 +: 32];
        return 32'h0;
    endfunction

    function automatic logic [7:0] pack_mask(input logic [NUM_ENCODERS-1:0] vec);
        logic [7:0] out;
        out = '0;
        for (int i = 0; i < NUM_ENCODERS; i++)
            out[i] = vec[i];
        return out;
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            nss_meta        <= 1'b1;
            nss_sync        <= 1'b1;
            nss_prev        <= 1'b1;
            sck_meta        <= '0;
            sck_sync        <= '0;
            sck_prev        <= '0;
            mosi_meta       <= '0;
            mosi_sync       <= '0;
            rx_shift        <= '0;
            rx_bit_cnt      <= '0;
            tx_shift        <= '0;
            tx_bit_cnt      <= '0;
            tx_pending      <= '0;
            tx_len          <= '0;
            tx_idx          <= '0;
            cmd_taken       <= '0;
            cfg_rx_phase    <= '0;
            cfg_gray_mask   <= 8'hFF;
            cfg_auto_poll   <= 1'b1;
            poll_req        <= '0;
            spi_miso        <= '0;
       
         end else begin
            poll_req <= '0;

            nss_meta  <= spi_nss;
            nss_sync  <= nss_meta;
            nss_prev  <= nss_sync;
            sck_meta  <= spi_sck;
            sck_sync  <= sck_meta;
            sck_prev  <= sck_sync;
            mosi_meta <= spi_mosi;
            mosi_sync <= mosi_meta;

            if (nss_rise) begin
                rx_bit_cnt      <= '0;
                tx_bit_cnt      <= '0;
                tx_pending      <= '0;
                cmd_taken       <= '0;
                cfg_rx_phase    <= '0;
                spi_miso        <= '0;
            end

            if (nss_fall) begin
                rx_bit_cnt  <= '0;
                tx_bit_cnt  <= '0;
                tx_idx      <= '0;
                tx_len      <= '0;
                tx_pending  <= '0;
                tx_shift    <= '0;
                cmd_taken   <= '0;
            end

            if (active && tx_pending && sck_fall)begin
                spi_miso <= tx_shift[7];
            
            end else if (!active) begin
                spi_miso <= '0;
            end

            if (active && sck_rise) begin
                rx_shift <= {rx_shift[6:0], mosi_sync};

                if (rx_bit_cnt == 3'd7) begin
                    logic [7:0]  rx_byte;
                    logic [31:0] value;
                    int          e, k, base;

                    rx_byte    = {rx_shift[6:0], mosi_sync};
                    rx_bit_cnt <= '0;

                    if (cfg_rx_phase == 2'd1) begin
                        cfg_gray_mask <= rx_byte;
                        cfg_rx_phase  <= 2'd2;

                    end else if (cfg_rx_phase == 2'd2) begin
                        cfg_auto_poll <= rx_byte[0];
                        cfg_rx_phase  <= '0;
                        tx_len        <= 1'b1;
                        tx_shift      <= 8'hAA;
                        tx_pending    <= 1'b1;
                        tx_idx        <= '0;
                        tx_bit_cnt    <= '0;

                    end else if (cfg_rx_phase == 0 && !cmd_taken) begin
                        tx_pending <= 1'b1;
                        tx_idx     <= '0;
                        tx_bit_cnt <= '0;

                        unique case (rx_byte)
                           
                            CMD_NOP: begin
                                tx_len   <= 1'b1;
                                tx_shift <= 8'h55;
                            end
                           
                            CMD_WRITE_CFG: begin
                                cfg_rx_phase <= 2'd1;
                                tx_pending   <= '0;
                            end
                        
                            CMD_TRIGGER_POLL: begin
                                poll_req <= 1'b1;
                                tx_len   <= 1'b1;
                                tx_shift <= poll_busy ? 8'h01 : 8'h00;
                            end
                          
                            CMD_READ_STATUS: begin
                                tx_len   <= 1'b1;
                                tx_shift <= status;
                            end
                         
                            CMD_READ_FAULT: begin
                                tx_len   <= 1'b1;
                                tx_shift <= pack_mask(enc_fault_mask);
                            end
                           
                            CMD_READ_ERROR: begin
                                tx_len   <= 1'b1;
                                tx_shift <= pack_mask(enc_error_mask);
                            end
                            
                            CMD_READ_VALID: begin
                                tx_len   <= 1'b1;
                                tx_shift <= pack_mask(enc_valid_mask);
                            end
                          
                            CMD_READ_ALL_POS: begin
                                base = 0;
                               
                                for (e = 0; e < NUM_ENCODERS; e++) begin
                                    value = get_word(enc_pos_flat, e);
                                    
                                    for (k = 0; k < 4; k++) begin
                                        tx_buf[base + k] = value[31 - k*8 -: 8];
                                    end
                                    
                                    tx_buf[base + 4] = calc_crc8(value);
                                    base += 5;
                                end

                                tx_len   <= PAYLOAD_MAX;
                                tx_shift <= tx_buf[0];
                            end

                            CMD_READ_ALL_RAW: begin
                                base = 0;

                                for (e = 0; e < NUM_ENCODERS; e++) begin
                                    value = get_word(enc_raw_flat, e);

                                    for (k = 0; k < 4; k++)begin
                                        tx_buf[base + k] = value[31 - k*8 -: 8];
                                    end

                                    tx_buf[base + 4] = calc_crc8(value);
                                    base += 5;
                                end

                                tx_len   <= PAYLOAD_MAX;
                                tx_shift <= tx_buf[0];
                            end

                             default: begin

                                if (rx_byte >= CMD_READ_ENC_BASE &&
                                    rx_byte <  CMD_READ_ENC_BASE + NUM_ENCODERS) begin
                                    value = get_word(enc_pos_flat, rx_byte - CMD_READ_ENC_BASE);
                                    
                                    for (k = 0; k < 4; k++)
                                        tx_buf[k] = value[31 - k*8 -: 8];

                                    tx_buf[4] = calc_crc8(value);
                                    tx_len    <= 3'd5;
                                    tx_shift  <= tx_buf[0];
                               
                                end else if (rx_byte >= CMD_READ_RAW_BASE &&
                                             rx_byte <  CMD_READ_RAW_BASE + NUM_ENCODERS) begin
                                    value = get_word(enc_raw_flat, rx_byte - CMD_READ_RAW_BASE);
                                  
                                    for (k = 0; k < 4; k++)
                                        tx_buf[k] = value[31 - k*8 -: 8];

                                    tx_buf[4] = calc_crc8(value);
                                    tx_len    <= 3'd5;
                                    tx_shift  <= tx_buf[0];
                               
                                end else begin
                                    tx_len   <= 1'd1;
                                    tx_shift <= 8'hEE;
                                end
                             end
                         endcase

                       cmd_taken <= 1'b1;
                     end

                end else
                    rx_bit_cnt <= rx_bit_cnt + 1'b1;
            end

            if (active && sck_fall && tx_pending) begin
              
                tx_shift <= tx_shift << 1;
                
                if (tx_bit_cnt == 3'd7) begin
                    tx_bit_cnt <= '0;
                    
                    if ((tx_idx + 1'b1) < tx_len) begin
                         tx_idx   <= tx_idx + 1'b1;
                         tx_shift <= tx_buf[tx_idx + 1'b1];
                    end else begin
                         tx_pending <= '0;
                    end
                end else begin
                     tx_bit_cnt <= tx_bit_cnt + 1'b1;
                end
             end
         end
    end

endmodule
