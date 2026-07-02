module FIFO #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4,
    localparam DEPTH = (1 << ADDR_W) //depth= 2^ADDR_W
) (
    input logic clk,
    input logic rst,

     // WRITE STREAM
    input  logic [DATA_W-1:0]     in_data,
    input  logic                  in_valid,
    output logic                  in_ready,

    // READ STREAM
    output logic [DATA_W-1:0]     out_data,
    output logic                  out_valid,
    input  logic                  out_ready,
     // TEST LED
    output logic test_led
);
//memory
logic [ADDR_W-1:0] mem [0:DEPTH-1];

//pointers
logic [ADDR_W:0] wr_bin, rd_bin;

// ============================================================
// STATUS
// ============================================================

 // FULL
assign in_ready  = !({~wr_bin[ADDR_W],wr_bin[ADDR_W-1:0]} == rd_bin);

// EMPTY
assign out_valid = !(wr_bin == rd_bin);

// ============================================================
// WRITE DOMAIN
// ============================================================
always_ff @(posedge clk or posedge rst) begin

    if (rst) begin
        wr_bin <= 0;
        rd_bin <= 0;
    end else begin
        if (in_valid && in_ready) begin
            mem[wr_bin[DATA_W-1:0]] <= in_data;
            wr_bin <= wr_bin + 1;
        end

        out_data <= mem[rd_bin[DATA_W-1:0]];

        if (out_valid && out_ready) begin
            rd_bin <= rd_bin + 1; 
        end
    end 
end

endmodule