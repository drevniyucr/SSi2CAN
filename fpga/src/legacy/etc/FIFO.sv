module fifo_stream #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
)(
    input  wire                     clk,
    input  wire                     rst,

    // INPUT STREAM
    input  wire [DATA_WIDTH-1:0]    in_data,
    input  wire                     in_valid,
    output wire                     in_ready,

    // OUTPUT STREAM
    output wire [DATA_WIDTH-1:0]    out_data,
    output wire                     out_valid,
    input  wire                     out_ready,

    // OPTIONAL STATUS
    output wire                     full,
    output wire                     empty
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // ============================================================
    // MEMORY
    // ============================================================

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ============================================================
    // POINTERS
    // ============================================================

    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    // ============================================================
    // STATUS
    // ============================================================

    assign empty =
        (wr_ptr == rd_ptr);

    assign full =
        (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    // ============================================================
    // STREAM INTERFACE
    // ============================================================

    assign in_ready  = !full;
    assign out_valid = !empty;

    // ============================================================
    // HANDSHAKES
    // ============================================================

    wire write_fire;
    wire read_fire;

    assign write_fire = in_valid  && in_ready;
    assign read_fire  = out_valid && out_ready;

    // ============================================================
    // WRITE LOGIC
    // ============================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
        end
        else begin
            if (write_fire) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= in_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    // ============================================================
    // READ LOGIC
    // ============================================================

   assign out_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_ptr <= 0;
        end
        else begin
            if (read_fire) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule