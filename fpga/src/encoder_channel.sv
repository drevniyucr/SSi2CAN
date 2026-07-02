// Один SSI-канал: reader + Gray→Binary
module encoder_channel #(
    parameter int DATA_BITS,
    parameter int CLK_DIV,
    parameter int T_IDLE,
    parameter int PAD_W
) (
    input  logic clk,
    input  logic rst,

    input  logic start,
    output logic busy,
    output logic done,
    output logic error,

    input  logic ssi_data,
    output logic ssi_clk,

    output logic [31:0] raw_ext,
    output logic [31:0] bin_pos
);

    logic [DATA_BITS-1:0] raw_sample;

    ssi_reader #(
        .DATA_BITS (DATA_BITS),
        .CLK_DIV   (CLK_DIV),
        .T_IDLE    (T_IDLE)
    ) u_ssi (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .busy     (busy),
        .done     (done),
        .error    (error),
        .ssi_data (ssi_data),
        .ssi_clk  (ssi_clk),
        .raw_data (raw_sample)
    );
 localparam int WIDTH = 32;
    generate
        if (PAD_W > 0)
            assign raw_ext = {{PAD_W{1'b0}}, raw_sample};
        else
            assign raw_ext = raw_sample[31:0];
    endgenerate

 always_comb begin
        bin_pos = raw_ext;
        for (int i = WIDTH - 2; i >= 0; i--)
            bin_pos[i] = bin_pos[i + 1] ^ raw_ext[i];
    end

endmodule
