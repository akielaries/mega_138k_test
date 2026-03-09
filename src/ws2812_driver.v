module ws2812_driver (
    input  wire clk,      // 50 MHz
    input  wire rstn,
    output reg  ws_out
);

    // ===============================
    // WS2812 timing
    // ===============================
    localparam T0H = 18;
    localparam T0L = 40;
    localparam T1H = 35;
    localparam T1L = 28;
    localparam RESET_TIME = 3000;

    // ===============================
    // Animation timing (0.5 sec)
    // ===============================
    reg [24:0] anim_counter;
    reg trigger;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            anim_counter <= 0;
            trigger <= 0;
        end else begin
            if (anim_counter == 25_000_000-1) begin
                anim_counter <= 0;
                trigger <= 1'b1;
            end else begin
                anim_counter <= anim_counter + 1;
                trigger <= 1'b0;
            end
        end
    end

    // ===============================
    // Color / brightness logic
    // ===============================
    reg [23:0] led_data;
    reg [1:0] color_state;
    localparam BRIGHT = 8'h20; // dim (~25%)

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            color_state <= 0;
            led_data <= {8'h00, BRIGHT, 8'h00}; // red (GRB)
        end else if (trigger) begin
            color_state <= color_state + 1;

            case(color_state)
                0: led_data <= {8'h00, BRIGHT, 8'h00}; // red
                1: led_data <= {BRIGHT, 8'h00, 8'h00}; // green
                2: led_data <= {8'h00, 8'h00, BRIGHT}; // blue
                default: led_data <= {8'h00, BRIGHT, 8'h00};
            endcase
        end
    end

    // ===============================
    // Existing WS2812 FSM
    // ===============================

    reg [15:0] timer;
    reg [5:0]  bit_idx;
    reg [2:0]  state;
    reg        busy;

    localparam IDLE=0, HIGH=1, LOW=2, RESET=3;

    wire current_bit = led_data[23-bit_idx];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ws_out<=0; timer<=0; bit_idx<=0;
            state<=IDLE; busy<=0;
        end else begin
            case(state)

            IDLE: begin
                ws_out<=0;
                timer<=0;
                bit_idx<=0;
                if(trigger && !busy) begin
                    busy<=1;
                    state<=HIGH;
                end
            end

            HIGH: begin
                ws_out<=1;
                if(timer==(current_bit?T1H:T0H)) begin
                    timer<=0;
                    state<=LOW;
                end else timer<=timer+1;
            end

            LOW: begin
                ws_out<=0;
                if(timer==(current_bit?T1L:T0L)) begin
                    timer<=0;
                    if(bit_idx==23)
                        state<=RESET;
                    else begin
                        bit_idx<=bit_idx+1;
                        state<=HIGH;
                    end
                end else timer<=timer+1;
            end

            RESET: begin
                ws_out<=0;
                if(timer==RESET_TIME) begin
                    timer<=0;
                    busy<=0;
                    state<=IDLE;
                end else timer<=timer+1;
            end
            endcase
        end
    end
endmodule
