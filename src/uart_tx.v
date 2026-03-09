module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115_200
)(
    input  clk,
    input  rstn,
    input  [7:0] data,
    input  valid,
    output reg ready,
    output reg tx
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;  // 434 @ 50MHz

    reg [9:0]  shift;   // start + 8 data + stop
    reg [15:0] baud_cnt;
    reg [3:0]  bit_cnt;
    reg        busy;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tx <= 1'b1; ready <= 1'b1; busy <= 0;
            baud_cnt <= 0; bit_cnt <= 0;
        end else if (!busy && valid) begin
            shift    <= {1'b1, data, 1'b0};  // stop, data[7:0], start
            baud_cnt <= 0;
            bit_cnt  <= 0;
            busy     <= 1;
            ready    <= 0;
        end else if (busy) begin
            if (baud_cnt == CLKS_PER_BIT - 1) begin
                baud_cnt <= 0;
                tx       <= shift[0];
                shift    <= {1'b1, shift[9:1]};
                bit_cnt  <= bit_cnt + 1;
                if (bit_cnt == 9) begin
                    busy  <= 0;
                    ready <= 1;
                end
            end else begin
                baud_cnt <= baud_cnt + 1;
            end
        end else begin
            tx    <= 1'b1;
            ready <= 1'b1;
        end
    end
endmodule