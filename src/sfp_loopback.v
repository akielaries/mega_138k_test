// =============================================================================
// sfp_loopback.v — 10.3125G SFP+ PRBS7 loopback tester
//
// Instantiates the Gowin SerDes_Top (Customized_PHY, GTR12_QUAD Q1) and
// runs a PRBS7 pattern on both SFP+ lanes.  With a DAC loopback cable the
// PRBS checker on each lane will lock within ~1 s of reset deassertion.
//
// Status outputs (active-high):
//   prbs_lock_ln0  — lane 0 RX locked to PRBS7 pattern (SFP0 path)
//   prbs_lock_ln1  — lane 1 RX locked to PRBS7 pattern (SFP1 path)
//   tx_act         — slow toggle driven from TX PCS clock (~1 Hz blink)
// =============================================================================

module sfp_loopback (
    input  rstn,                // active-low reset
    output sfp_tx_disable_ln0,  // drive low to enable SFP0 TX laser
    output sfp_tx_disable_ln1,  // drive low to enable SFP1 TX laser
    output prbs_lock_ln0,       // PRBS7 lock on lane 0 RX (gated)
    output prbs_lock_ln1,       // PRBS7 lock on lane 1 RX (gated)
    output tx_act,              // TX clock activity blink
    // Raw SerDes status for diagnostics (routed to APB sfp_regs.stat)
    output [21:0] serdes_stat,  // see bit definitions below
    // RX data snapshots — latched on rx_valid, readable via APB sfp_regs
    output reg [31:0] ln0_rx_snap,
    output reg [31:0] ln1_rx_snap,
    // TX control from APB sfp_regs
    input  tx_mode,             // 0=PRBS7 (default), 1=user pattern
    input  [31:0] tx_pattern    // user TX pattern (active when tx_mode=1)
);

    // Both SFP TX lasers always enabled
    assign sfp_tx_disable_ln0 = 1'b0;
    assign sfp_tx_disable_ln1 = 1'b0;

    // ENABLE_ENCODING=true means Customized_PHY_Top performs 8b/10b encoding.
    // Fabric interface uses {K, D[7:0]} format (bit[8]=K, bits[7:0]=D).
    // TX_ENCODING=OFF only means the GTR12_QUAD hardware encoder is bypassed;
    // the Customized_PHY wrapper encoder is still active (ENABLE_ENCODING=true).
    // K28.5: K=1, D=0xBC → {1'b0, 1'b1, 8'hBC} = 10'h1BC
    wire [9:0] COMMA = {1'b0, 1'b1, 8'hBC}; // K28.5: K=1, D=0xBC

    // =========================================================================
    // SerDes_Top interface wires — Lane 1
    // =========================================================================
    wire        ln1_rx_pcs_clk;
    wire [87:0] ln1_rx_data;
    wire [4:0]  ln1_rx_fifo_rdusewd;
    wire        ln1_rx_fifo_aempty;
    wire        ln1_rx_fifo_empty;
    wire        ln1_rx_valid;
    wire        ln1_tx_pcs_clk;
    wire [4:0]  ln1_tx_fifo_wrusewd;
    wire        ln1_tx_fifo_afull;
    wire        ln1_tx_fifo_full;
    wire        ln1_refclk;
    wire        ln1_signal_detect;
    wire        ln1_rx_cdr_lock;
    wire        ln1_pll_lock;
    wire        ln1_k_lock;
    wire        ln1_word_align_link;
    wire        ln1_ready;
    wire [79:0] ln1_tx_data;

    // =========================================================================
    // SerDes_Top interface wires — Lane 0
    // =========================================================================
    wire        ln0_rx_pcs_clk;
    wire [87:0] ln0_rx_data;
    wire [4:0]  ln0_rx_fifo_rdusewd;
    wire        ln0_rx_fifo_aempty;
    wire        ln0_rx_fifo_empty;
    wire        ln0_rx_valid;
    wire        ln0_tx_pcs_clk;
    wire [4:0]  ln0_tx_fifo_wrusewd;
    wire        ln0_tx_fifo_afull;
    wire        ln0_tx_fifo_full;
    wire        ln0_refclk;
    wire        ln0_signal_detect;
    wire        ln0_rx_cdr_lock;
    wire        ln0_pll_lock;
    wire        ln0_k_lock;
    wire        ln0_word_align_link;
    wire        ln0_ready;
    wire [79:0] ln0_tx_data;

    // =========================================================================
    // SerDes_Top instantiation
    // =========================================================================
    SerDes_Top serdes_top_inst (
        // Lane 1 outputs
        .Customized_PHY_Top_q1_ln1_rx_pcs_clkout_o   (ln1_rx_pcs_clk),
        .Customized_PHY_Top_q1_ln1_rx_data_o          (ln1_rx_data),
        .Customized_PHY_Top_q1_ln1_rx_fifo_rdusewd_o  (ln1_rx_fifo_rdusewd),
        .Customized_PHY_Top_q1_ln1_rx_fifo_aempty_o   (ln1_rx_fifo_aempty),
        .Customized_PHY_Top_q1_ln1_rx_fifo_empty_o    (ln1_rx_fifo_empty),
        .Customized_PHY_Top_q1_ln1_rx_valid_o         (ln1_rx_valid),
        .Customized_PHY_Top_q1_ln1_tx_pcs_clkout_o    (ln1_tx_pcs_clk),
        .Customized_PHY_Top_q1_ln1_tx_fifo_wrusewd_o  (ln1_tx_fifo_wrusewd),
        .Customized_PHY_Top_q1_ln1_tx_fifo_afull_o    (ln1_tx_fifo_afull),
        .Customized_PHY_Top_q1_ln1_tx_fifo_full_o     (ln1_tx_fifo_full),
        .Customized_PHY_Top_q1_ln1_refclk_o           (ln1_refclk),
        .Customized_PHY_Top_q1_ln1_signal_detect_o    (ln1_signal_detect),
        .Customized_PHY_Top_q1_ln1_rx_cdr_lock_o      (ln1_rx_cdr_lock),
        .Customized_PHY_Top_q1_ln1_pll_lock_o         (ln1_pll_lock),
        .Customized_PHY_Top_q1_ln1_k_lock_o           (ln1_k_lock),
        .Customized_PHY_Top_q1_ln1_word_align_link_o  (ln1_word_align_link),
        .Customized_PHY_Top_q1_ln1_ready_o            (ln1_ready),
        // Lane 1 inputs
        .Customized_PHY_Top_q1_ln1_rx_clk_i           (ln1_rx_pcs_clk),
        .Customized_PHY_Top_q1_ln1_rx_fifo_rden_i     (~ln1_rx_fifo_aempty),
        .Customized_PHY_Top_q1_ln1_tx_clk_i           (ln1_tx_pcs_clk),
        .Customized_PHY_Top_q1_ln1_tx_data_i          (ln1_tx_data),
        .Customized_PHY_Top_q1_ln1_tx_fifo_wren_i     (~ln1_tx_fifo_afull),
        .Customized_PHY_Top_q1_ln1_pma_rstn_i         (1'b1),
        .Customized_PHY_Top_q1_ln1_pcs_rx_rst_i       (ln1_pcs_rx_rst),
        .Customized_PHY_Top_q1_ln1_pcs_tx_rst_i       (ln1_pcs_tx_rst),

        // Lane 0 outputs
        .Customized_PHY_Top_q1_ln0_rx_pcs_clkout_o   (ln0_rx_pcs_clk),
        .Customized_PHY_Top_q1_ln0_rx_data_o          (ln0_rx_data),
        .Customized_PHY_Top_q1_ln0_rx_fifo_rdusewd_o  (ln0_rx_fifo_rdusewd),
        .Customized_PHY_Top_q1_ln0_rx_fifo_aempty_o   (ln0_rx_fifo_aempty),
        .Customized_PHY_Top_q1_ln0_rx_fifo_empty_o    (ln0_rx_fifo_empty),
        .Customized_PHY_Top_q1_ln0_rx_valid_o         (ln0_rx_valid),
        .Customized_PHY_Top_q1_ln0_tx_pcs_clkout_o    (ln0_tx_pcs_clk),
        .Customized_PHY_Top_q1_ln0_tx_fifo_wrusewd_o  (ln0_tx_fifo_wrusewd),
        .Customized_PHY_Top_q1_ln0_tx_fifo_afull_o    (ln0_tx_fifo_afull),
        .Customized_PHY_Top_q1_ln0_tx_fifo_full_o     (ln0_tx_fifo_full),
        .Customized_PHY_Top_q1_ln0_refclk_o           (ln0_refclk),
        .Customized_PHY_Top_q1_ln0_signal_detect_o    (ln0_signal_detect),
        .Customized_PHY_Top_q1_ln0_rx_cdr_lock_o      (ln0_rx_cdr_lock),
        .Customized_PHY_Top_q1_ln0_pll_lock_o         (ln0_pll_lock),
        .Customized_PHY_Top_q1_ln0_k_lock_o           (ln0_k_lock),
        .Customized_PHY_Top_q1_ln0_word_align_link_o  (ln0_word_align_link),
        .Customized_PHY_Top_q1_ln0_ready_o            (ln0_ready),
        // Lane 0 inputs
        .Customized_PHY_Top_q1_ln0_rx_clk_i           (ln0_rx_pcs_clk),
        .Customized_PHY_Top_q1_ln0_rx_fifo_rden_i     (~ln0_rx_fifo_aempty),
        .Customized_PHY_Top_q1_ln0_tx_clk_i           (ln0_tx_pcs_clk),
        .Customized_PHY_Top_q1_ln0_tx_data_i          (ln0_tx_data),
        .Customized_PHY_Top_q1_ln0_tx_fifo_wren_i     (~ln0_tx_fifo_afull),
        .Customized_PHY_Top_q1_ln0_pma_rstn_i         (1'b1),
        .Customized_PHY_Top_q1_ln0_pcs_rx_rst_i       (ln0_pcs_rx_rst),
        .Customized_PHY_Top_q1_ln0_pcs_tx_rst_i       (ln0_pcs_tx_rst)
    );

    // =========================================================================
    // Lane 1 — PRBS7 generator + checker
    // =========================================================================
    wire [7:0] ln1_prbs7_gen_data;
    wire [9:0] ln1_prbs7_10b = {2'b0, ln1_prbs7_gen_data};

    // TX: K28.5 comma + 7 data words.
    // tx_mode=0 (default): PRBS7 pattern — locks PRBS checker for link verification.
    // tx_mode=1 (user):    4 bytes of tx_pattern followed by 3 idle words — lets
    //                      firmware write a known value (e.g. 0xDEADBEEF) and read
    //                      it back via ln1_rx_snap.
    wire [9:0] upat_b0    = {1'b0, tx_pattern[7:0]};
    wire [9:0] upat_b1    = {1'b0, tx_pattern[15:8]};
    wire [9:0] upat_b2    = {1'b0, tx_pattern[23:16]};
    wire [9:0] upat_b3    = {1'b0, tx_pattern[31:24]};
    wire [9:0] upat_idle  = 10'h000;

    assign ln1_tx_data = tx_mode ?
        {COMMA, upat_idle, upat_idle, upat_idle, upat_b3, upat_b2, upat_b1, upat_b0} :
        {COMMA, {7{ln1_prbs7_10b}}};

    // RX: extract byte after comma alignment
    reg [7:0] ln1_prbs7_chk_data;
    always @(*) begin
        if (ln1_rx_data[8:0] == 9'h1_BC)
            ln1_prbs7_chk_data = ln1_rx_data[17:10];
        else
            ln1_prbs7_chk_data = ln1_rx_data[7:0];
    end

    wire ln1_prbs_lock_raw;
    prbs7_single_channel #(.WIDTH(8)) ln1_prbs7 (
        .tx_clk_i   (ln1_tx_pcs_clk),
        .tx_rstn_i  (rstn),
        .tx_en_i    (1'b1),
        .tx_data_o  (ln1_prbs7_gen_data),
        .rx_clk_i   (ln1_rx_pcs_clk),
        .rx_rstn_i  (ln1_word_align_link),
        .rx_en_i    (1'b1),
        .rx_data_i  (ln1_prbs7_chk_data),
        .lock_o     (ln1_prbs_lock_raw)
    );
    assign prbs_lock_ln1 = ln1_prbs_lock_raw & ln1_signal_detect & ln1_rx_cdr_lock & ln1_k_lock;

    // =========================================================================
    // Lane 0 — PRBS7 generator + checker
    // =========================================================================
    wire [7:0] ln0_prbs7_gen_data;
    wire [9:0] ln0_prbs7_10b = {2'b0, ln0_prbs7_gen_data};

    assign ln0_tx_data = tx_mode ?
        {COMMA, upat_idle, upat_idle, upat_idle, upat_b3, upat_b2, upat_b1, upat_b0} :
        {COMMA, {7{ln0_prbs7_10b}}};

    reg [7:0] ln0_prbs7_chk_data;
    always @(*) begin
        if (ln0_rx_data[8:0] == 9'h1_BC)
            ln0_prbs7_chk_data = ln0_rx_data[17:10];
        else
            ln0_prbs7_chk_data = ln0_rx_data[7:0];
    end

    wire ln0_prbs_lock_raw;
    prbs7_single_channel #(.WIDTH(8)) ln0_prbs7 (
        .tx_clk_i   (ln0_tx_pcs_clk),
        .tx_rstn_i  (rstn),
        .tx_en_i    (1'b1),
        .tx_data_o  (ln0_prbs7_gen_data),
        .rx_clk_i   (ln0_rx_pcs_clk),
        .rx_rstn_i  (ln0_word_align_link),
        .rx_en_i    (1'b1),
        .rx_data_i  (ln0_prbs7_chk_data),
        .lock_o     (ln0_prbs_lock_raw)
    );
    assign prbs_lock_ln0 = ln0_prbs_lock_raw & ln0_signal_detect & ln0_rx_cdr_lock & ln0_k_lock;

    // =========================================================================
    // TX activity blink — ~1 Hz from ln0 TX PCS clock (156.25 MHz / 2^27)
    // =========================================================================
    reg [26:0] act_cnt = 27'b0;
    always @(posedge ln0_tx_pcs_clk) act_cnt <= act_cnt + 1'b1;
    assign tx_act = act_cnt[26];

    // =========================================================================
    // PCS resets — held deasserted (0) so the IP manages its own bring-up.
    // The Customized_PHY_Top handles CDR lock internally before enabling the
    // word aligner; no fabric-driven reset is needed or beneficial.
    // (Matches the Gowin reference example exactly.)
    // =========================================================================
    wire ln0_pcs_tx_rst = 1'b0;
    wire ln1_pcs_tx_rst = 1'b0;
    wire ln0_pcs_rx_rst = 1'b0;
    wire ln1_pcs_rx_rst = 1'b0;

    // =========================================================================
    // RX data snapshots — latch first rx_valid word into 32-bit registers.
    // Readable via APB at 0x6000_0030 (ln0) and 0x6000_0034 (ln1).
    // Holds last captured value; useful for confirming comma + data arrival.
    // =========================================================================
    always @(posedge ln0_rx_pcs_clk or negedge rstn) begin
        if (!rstn) ln0_rx_snap <= 32'h0;
        else if (ln0_rx_valid) ln0_rx_snap <= ln0_rx_data[31:0];
    end

    always @(posedge ln1_rx_pcs_clk or negedge rstn) begin
        if (!rstn) ln1_rx_snap <= 32'h0;
        else if (ln1_rx_valid) ln1_rx_snap <= ln1_rx_data[31:0];
    end

    // =========================================================================
    // SerDes diagnostic status — routed to APB gpio_stat (0x60000024)
    //   [0]  ln0_signal_detect
    //   [1]  ln0_rx_cdr_lock
    //   [2]  ln0_k_lock
    //   [3]  ln0_word_align_link
    //   [4]  ln0_pll_lock
    //   [5]  ln0_ready
    //   [6]  ln0_prbs_lock (raw)
    //   [7]  reserved
    //   [8]  ln1_signal_detect
    //   [9]  ln1_rx_cdr_lock
    //   [10] ln1_k_lock
    //   [11] ln1_word_align_link
    //   [12] ln1_pll_lock
    //   [13] ln1_ready
    //   [14] ln0_rx_valid
    //   [15] ln0_rx_fifo_empty
    //   [16] ln1_rx_valid
    //   [17] ln1_rx_fifo_empty
    //   [18] ln0_tx_fifo_afull  (TX FIFO almost-full: if stuck=1 writes are blocked)
    //   [19] ln0_tx_fifo_full
    //   [20] ln1_tx_fifo_afull
    //   [21] ln1_tx_fifo_full
    // =========================================================================
    assign serdes_stat = {
        ln1_tx_fifo_full, ln1_tx_fifo_afull, ln0_tx_fifo_full, ln0_tx_fifo_afull, // [21:18]
        ln1_rx_fifo_empty, ln1_rx_valid, ln0_rx_fifo_empty, ln0_rx_valid,   // [17:14]
        ln1_ready, ln1_pll_lock, ln1_word_align_link, ln1_k_lock, ln1_rx_cdr_lock, ln1_signal_detect, // [13:8]
        ln1_prbs_lock_raw,                                                    // [7]
        ln0_prbs_lock_raw, ln0_ready, ln0_pll_lock, ln0_word_align_link, ln0_k_lock, ln0_rx_cdr_lock, ln0_signal_detect // [6:0]
    };

endmodule
