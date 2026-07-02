// module CRC32(
//     input wire clk,
//     input wire rst,
//     input wire[255:0] buff_in,
//     input wire crc_start,

//     output reg [287:0] buff_out,
//     output reg crc_done 
// );
//     parameter POLYNOMIAL = 32'hEDB88320;
//     parameter EncPackSize = 32;

//     reg  [31:0]  crc_reg;
//     reg  [31:0]  byte_count; 
//     reg   [7:0]  data_byte;
//     reg [255:0]  RegBuffIn;
//     reg  [31:0]  bit_index;
//     reg  [31:0]  count;
    

//     typedef enum reg [5:0] {
//         IDLE,
//         LOAD,
//         LOAD_BYTE,
//         XOR_STAGE,
//         PROCESS,
//         DONE 
//     } state_t;

//     state_t state = IDLE;
//     // FSM: действия
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state      <= IDLE;
//             crc_done   <= 0;
//             crc_reg    <= 32'hFFFFFFFF;
//             byte_count <= 0;
//             bit_index  <= 0;
//             buff_out   <= 0;
//             RegBuffIn  <= 0;
//             data_byte  <= 0;
        
//         end else begin
//             case (state)
//                 IDLE: begin
//                     crc_done   <= 0;
//                     byte_count <= 0;
//                     bit_index  <= 0;
//                     crc_reg    <= 32'hFFFFFFFF;
//                     if (crc_start) state <= LOAD;
//                 end
//                 LOAD: begin
//                     RegBuffIn  <= buff_in;
//                     state      <= LOAD_BYTE;
//                 end

//                 LOAD_BYTE:begin
//                     data_byte <= RegBuffIn[(EncPackSize - 1 - byte_count) * 8 +: 8];
//                     bit_index <= 0;
//                     state     <= XOR_STAGE;
//                 end

//                  XOR_STAGE: begin
//                     crc_reg <= crc_reg ^ data_byte;
//                     state   <= PROCESS;
//                 end

//                 PROCESS: begin
//                     if (bit_index < 8) begin
//                         bit_index <= bit_index + 1;

//                         if (crc_reg[0]) crc_reg <= (crc_reg >> 1) ^ POLYNOMIAL;                           
//                         else crc_reg <= crc_reg >> 1; 
//                     end else begin 
//                         byte_count <= byte_count + 1; 

//                         if (byte_count == EncPackSize-1) state <= DONE;
//                         else state <= LOAD_BYTE;
//                     end
//                 end

//                 DONE: begin
//                     crc_done          <= 1;
//                     buff_out[31:0]    <= ~crc_reg;           
//                     buff_out[287:32]  <= RegBuffIn;

//                     //if (crc_done_reg)                  CRC_DONE <= 0;
//                     //if (!CRC_START && !crc_done_reg)   state   <= IDLE;       
//                 end

//                 default: state <= IDLE;
//             endcase
//             end
//         end
//     endmodule