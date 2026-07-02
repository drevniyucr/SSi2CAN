// =============================================================================
// ssi_reader — мастер SSI для одного энкодера
//
// Тактирование SSI: clk idle = высокий. По старту после паузы T_IDLE
// генерируются DATA_BITS+1 импульсов: на каждом нарастающем фронте ssi_clk
// читается бит (MSB первым). Последний (DATA_BITS-й) фронт — контрольный:
// если линия DATA осталась высокой (нет монофлоп-«0» от энкодера) -> error=1
// (обрыв линии / отсутствие энкодера).
// =============================================================================
module ssi_reader #(
    parameter int DATA_BITS,
    parameter int CLK_DIV,
    parameter int T_IDLE
) (
    input  logic clk,
    input  logic rst,

    input  logic start,
    output logic busy,
    output logic done,
    output logic error,

    input  logic ssi_data,
    output logic ssi_clk,

    output logic [DATA_BITS-1:0] raw_data
);

    localparam int IDLE_W = (T_IDLE  <= 1) ? 1 : $clog2(T_IDLE);
    localparam int CLK_W  = (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
    localparam int BIT_W  = $clog2(DATA_BITS + 2);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT,
        ST_RUN,
        ST_DONE
    } state_t;

    state_t state = ST_IDLE;

    logic [IDLE_W-1:0] idle_cnt = '0;
    logic [CLK_W-1:0]  div_cnt  = '0;
    logic [BIT_W-1:0]  bit_cnt  = '0;
    logic              sclk     = 1'b1;

    assign busy    = (state != ST_IDLE);
    assign ssi_clk = sclk;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= ST_IDLE;
            idle_cnt <= '0;
            div_cnt  <= '0;
            bit_cnt  <= '0;
            sclk     <= 1'b1;
            raw_data <= '0;
            done     <= 1'b0;
            error    <= 1'b0;

        end else begin
            done <= 1'b0;

            unique case (state)

                ST_IDLE: begin
                    sclk     <= 1'b1;
                    div_cnt  <= '0;
                    bit_cnt  <= '0;
                    idle_cnt <= '0;
                    if (start) begin
                        raw_data <= '0;
                        error    <= 1'b0;
                        state    <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (idle_cnt == T_IDLE - 1) begin
                        div_cnt <= '0;
                        sclk    <= 1'b1;
                        state   <= ST_RUN;
                    end else
                        idle_cnt <= idle_cnt + 1'b1;
                end

                ST_RUN: begin
                    if (div_cnt == CLK_DIV - 1) begin
                        div_cnt <= '0;
                        sclk    <= ~sclk;

                        // нарастающий фронт ssi_clk (sclk 0 -> 1): читаем бит
                        if (!sclk) begin

                            if ((bit_cnt < DATA_BITS + 1'b1) && (bit_cnt > 1'b0)) begin
                                raw_data <= {raw_data[DATA_BITS-2:0], ssi_data};
                            end 
                            
                                bit_cnt <= bit_cnt + 1'b1;
                        end 

                        else if (sclk && (bit_cnt >= DATA_BITS + 1'b1)) begin
                            error <= ssi_data;
                            state <= ST_DONE;
                        end
                    end 

                    else
                        div_cnt <= div_cnt + 1'b1;
                end

                ST_DONE: begin
                    sclk  <= 1'b1;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
