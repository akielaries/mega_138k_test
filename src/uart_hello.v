module uart_hello (
    input  clk,
    input  rstn,
    output tx
);
    // "Hello World!\r\n" = 14 bytes
    reg [7:0] msg [0:13];
    reg [3:0] idx;
    reg       sent;

    initial begin
        msg[0]  = "H"; msg[1]  = "e"; msg[2]  = "l"; msg[3]  = "l";
        msg[4]  = "o"; msg[5]  = " "; msg[6]  = "W"; msg[7]  = "o";
        msg[8]  = "r"; msg[9]  = "l"; msg[10] = "d"; msg[11] = "!";
        msg[12] = "\n";
    end

    wire       ready;
    reg        valid;
    reg [7:0]  data;

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD(115_200)) utx (
        .clk(clk), .rstn(rstn),
        .data(data), .valid(valid),
        .ready(ready), .tx(tx)
    );

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            idx   <= 0;
            valid <= 0;
            sent  <= 0;
        end else if (!sent) begin
            if (ready && !valid) begin
                data  <= msg[idx];
                valid <= 1;
            end else if (valid) begin
                valid <= 0;
                if (idx == 13)
                    sent <= 1;   // done — comment out to repeat forever
                else
                    idx <= idx + 1;
            end
        end
    end
endmodule