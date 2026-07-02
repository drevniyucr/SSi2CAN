`timescale 1ns/1ps

module tb_fifo_stream;

    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 16;

    reg                     clk;
    reg                     rst;

    reg  [DATA_WIDTH-1:0]   in_data;
    reg                     in_valid;
    wire                    in_ready;

    wire [DATA_WIDTH-1:0]   out_data;
    wire                    out_valid;
    reg                     out_ready;

    wire                    full;
    wire                    empty;

initial begin
    $dumpfile("fifo.vcd");
    $dumpvars(0, tb_fifo_stream);
     clk = 0;
    forever #5 clk = ~clk;
end

    fifo_stream #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk       (clk),
        .rst       (rst),

        .in_data   (in_data),
        .in_valid  (in_valid),
        .in_ready  (in_ready),

        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready),

        .full      (full),
        .empty     (empty)
    );

    //---------------------------------------------------------
    // CLOCK
    //---------------------------------------------------------


    //---------------------------------------------------------
    // WRITE TASK
    //---------------------------------------------------------

    task automatic push(input [7:0] data);
    begin
        @(posedge clk);

        while (!in_ready)
            @(posedge clk);

        in_data  <= data;
        in_valid <= 1'b1;

        @(posedge clk);

        in_valid <= 1'b0;
    end
    endtask

    //---------------------------------------------------------
    // READ TASK
    //---------------------------------------------------------

    task automatic pop(output [7:0] data);
    begin
         while (!out_valid)
            @(posedge clk);
         @(posedge clk);   // ровно один handshake
        data = out_data;
        out_ready = 1'b1;

        @(posedge clk);   // ровно один handshake
        out_ready = 1'b0;
    end
    endtask

    //---------------------------------------------------------
    // TEST
    //---------------------------------------------------------

    integer i;
    reg [7:0] rx;

    initial begin

        rst       = 1;
        in_valid  = 0;
        in_data   = 0;
        out_ready = 0;

        repeat(5) @(posedge clk);

        rst = 0;

        //-----------------------------------------------------
        // FIFO must be empty after reset
        //-----------------------------------------------------

        if (!empty) begin
            $display("ERROR: FIFO not empty after reset");
            $fatal;
        end

        //-----------------------------------------------------
        // Write 4 bytes
        //-----------------------------------------------------

        push(8'h11);
        push(8'h22);
        push(8'h33);
        push(8'h44);

        //-----------------------------------------------------
        // Read back and verify order
        //-----------------------------------------------------

        pop(rx);
        if (rx !== 8'h11) begin
            $display("ERROR expected 11 got %02h", rx);
            $fatal;
        end

        pop(rx);
        if (rx !== 8'h22) begin
            $display("ERROR expected 22 got %02h", rx);
            $fatal;
        end

        pop(rx);
        if (rx !== 8'h33) begin
            $display("ERROR expected 33 got %02h", rx);
            $fatal;
        end

        pop(rx);
        if (rx !== 8'h44) begin
            $display("ERROR expected 44 got %02h", rx);
            $fatal;
        end

        //-----------------------------------------------------
        // Must be empty again
        //-----------------------------------------------------
        @(posedge clk);   // ровно один handshake
        if (!empty) begin
            $display("ERROR: FIFO should be empty");
            $fatal;
        end

        //-----------------------------------------------------
        // Fill FIFO completely
        //-----------------------------------------------------

        for (i = 0; i < DEPTH; i = i + 1)
            push(i);

         @(posedge clk);   // ровно один handshake
        if (!full) begin
            $display("ERROR: FIFO should be full");
            $fatal;
        end

        //-----------------------------------------------------
        // Drain FIFO
        //-----------------------------------------------------

        for (i = 0; i < DEPTH; i = i + 1) begin

            pop(rx);

            if (rx !== i[7:0]) begin
                $display(
                    "ERROR idx=%0d expected=%02h got=%02h",
                    i,
                    i[7:0],
                    rx
                );
                $fatal;
            end
        end
        @(posedge clk);   // ровно один handshake
        if (!empty) begin
            $display("ERROR: FIFO should be empty after drain");
            $fatal;
        end

        $display("TEST PASSED");

        #100;
        $finish;
    end

endmodule