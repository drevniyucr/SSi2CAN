// =============================================================================
// encoder_ctrl — контроллер параллельного опроса SSI-энкодеров
//
// Маски состояния (обновляются в конце каждого опроса, в ST_COLLECT):
//   enc_valid_mask[i] — последний кадр канала i принят без ошибки
//   enc_error_mask[i] — последний кадр канала i с ошибкой (обрыв/all-ones)
//   enc_fault_mask[i] — фиксируемый признак неисправности: взводится при любой
//                       ошибке и держится до сброса (rst). Диагностическая защёлка.
// =============================================================================
module encoder_ctrl #(
    parameter int NUM_ENCODERS,
    parameter int DATA_BITS,
    parameter int CLK_DIV,
    parameter int T_IDLE,
    parameter int AUTO_PERIOD
) (
    input  logic clk,
    input  logic rst,

    input  logic [NUM_ENCODERS-1:0] ssi_data,
    output logic [NUM_ENCODERS-1:0] ssi_clk,

    input  logic poll_req,
    output logic poll_busy,

    input  logic [7:0] cfg_gray_mask,
    input  logic       cfg_auto_poll,

    output logic [NUM_ENCODERS-1:0] enc_error_mask,
    output logic [NUM_ENCODERS-1:0] enc_valid_mask,
    output logic [NUM_ENCODERS-1:0] enc_fault_mask,

    output logic [NUM_ENCODERS-1:0] enc_leds,

    output logic [NUM_ENCODERS*32-1:0] enc_pos_data,
    output logic [NUM_ENCODERS*32-1:0] enc_raw_data,

    output logic [7:0] status
);

    localparam int PAD_W = (DATA_BITS < 32) ? (32 - DATA_BITS) : 0;

    logic [NUM_ENCODERS*32-1:0] enc_bin_data;
    logic [NUM_ENCODERS-1:0] sample_error;
    logic [NUM_ENCODERS-1:0] seq_start = '0;
    logic [NUM_ENCODERS-1:0] seq_busy;
    logic [NUM_ENCODERS-1:0] seq_done;

    logic [NUM_ENCODERS-1:0] latched_sample_err = '0;
    logic [NUM_ENCODERS-1:0] done_mask = '0;

    logic [$clog2(AUTO_PERIOD)-1:0] auto_cnt = '0;
    logic poll_armed = '0;
    logic auto_trigger;

    typedef enum logic [1:0]
    {
        ST_IDLE,
        ST_RUN,
        ST_COLLECT
    } state_t;

    state_t state = ST_IDLE;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_ENCODERS; gi++) begin : gen_ch
            encoder_channel #(
                .DATA_BITS (DATA_BITS),
                .CLK_DIV   (CLK_DIV),
                .T_IDLE    (T_IDLE),
                .PAD_W     (PAD_W)
            ) u_ch (
                .clk      (clk),
                .rst      (rst),
                .start    (seq_start[gi]),
                .busy     (seq_busy[gi]),
                .done     (seq_done[gi]),
                .error    (sample_error[gi]),
                .ssi_data (ssi_data[gi]),
                .ssi_clk  (ssi_clk[gi]),
                .raw_ext  (enc_raw_data[gi*32 +: 32]),
                .bin_pos  (enc_bin_data[gi*32 +: 32])
            );
        end
    endgenerate

    assign poll_busy = poll_armed || (|seq_busy);

    assign auto_trigger = cfg_auto_poll &&
                          (auto_cnt == AUTO_PERIOD - 1) && !poll_busy;

    // Авто-опрос
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            auto_cnt <= '0;
        else if (cfg_auto_poll) begin
            if (auto_cnt == AUTO_PERIOD-1)
                auto_cnt <= '0;
            else
                auto_cnt <= auto_cnt + 1'b1;
        end else
            auto_cnt <= '0;
    end

    // FSM опроса
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state              <= ST_IDLE;
            latched_sample_err <= '0;
            poll_armed         <= '0;
            done_mask          <= '0;
            enc_error_mask     <= '0;
            enc_valid_mask     <= '0;
            enc_fault_mask     <= '0;
            enc_leds           <= '0;
            enc_pos_data       <= '0;

        end else begin
            seq_start <= '0;
            enc_leds  <= ~enc_error_mask;

            unique case (state)

                ST_IDLE: begin
                    done_mask <= '0;

                    if ((poll_req | auto_trigger) && !poll_armed && !(|seq_busy)) begin
                        seq_start          <= {NUM_ENCODERS{1'b1}};
                        latched_sample_err <= '0;
                        poll_armed         <= 1'b1;
                        state              <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    done_mask <= done_mask | seq_done;
                    latched_sample_err <=
                        latched_sample_err | (seq_done & sample_error);

                    if (done_mask == {NUM_ENCODERS{1'b1}})
                        state <= ST_COLLECT;
                end

                ST_COLLECT: begin
                    for (int i = 0; i < NUM_ENCODERS; i++)
                        enc_pos_data[i*32 +: 32] <= cfg_gray_mask[i] ?
                            enc_bin_data[i*32 +: 32] : enc_raw_data[i*32 +: 32];

                    enc_error_mask <= latched_sample_err;
                    enc_valid_mask <= ~latched_sample_err;
                    enc_fault_mask <= enc_fault_mask | latched_sample_err; // sticky
                    poll_armed     <= '0;
                    state          <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // status-байт
    //   [2:0] NUM_ENCODERS-1, [3] busy, [4] any_valid,
    //   [5] any_fault, [6] any_error, [7] auto_poll
    always_comb begin
        status      = 8'h00;
        status[2:0] = 3'(NUM_ENCODERS - 1);
        status[3]   = poll_busy;
        status[4]   = |enc_valid_mask;
        status[5]   = |enc_fault_mask;
        status[6]   = |enc_error_mask;
        status[7]   = cfg_auto_poll;
    end

endmodule
