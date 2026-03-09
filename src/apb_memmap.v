module apb_memmap (
    input        APBCLK,
    input        APBRESET,
    input [31:0] PADDR,
    input        PSEL,
    input        PENABLE,
    input        PWRITE,
    input [31:0] PWDATA,
    output [31:0] PRDATA,
    output       PREADY,
    output       PSLVERR,
    // SFP status/data from sfp_loopback
    input [21:0] sfp_stat,
    input [31:0] ln0_rx_snap,
    input [31:0] ln1_rx_snap,
    // SFP control outputs to sfp_loopback
    output       tx_mode,
    output [31:0] tx_pattern
);

    // Peripheral offsets from APB1 base (0x6000_0000)
    //   sysinfo: 0x00–0x13  (system_info, 5 regs)
    //   gpio:    0x20–0x27  (gpio, 2 regs: out/stat)
    //   sfp:     0x40–0x53  (sfp_regs, 5 regs — placed here so PADDR[4:2] == register index)

    // sub-block wires
    wire [31:0] sysinfo_prdata;
    wire        sysinfo_pready;
    wire [31:0] gpio_prdata;
    wire        gpio_pready;
    wire [31:0] sfp_prdata;
    wire        sfp_pready;

    // address decode
    wire sysinfo_sel = PSEL && (PADDR[19:0] < 20'h14);
    wire gpio_sel    = PSEL && (PADDR[19:0] >= 20'h20 && PADDR[19:0] < 20'h28);
    wire sfp_sel     = PSEL && (PADDR[19:0] >= 20'h40 && PADDR[19:0] < 20'h54);

    // sysinfo
    system_info sysinfo_inst (
        .APBCLK  (APBCLK),
        .APBRESET(APBRESET),
        .PADDR   (PADDR),
        .PSEL    (PSEL & sysinfo_sel),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PRDATA  (sysinfo_prdata),
        .PREADY  (sysinfo_pready),
        .PSLVERR ()
    );

    // gpio — stat input left 0; gpio is purely for GPIO output control now
    wire [31:0] gpio_out;

    gpio gpio_inst (
        .APBCLK   (APBCLK),
        .APBRESET (APBRESET),
        .PADDR    (PADDR),
        .PSEL     (PSEL & gpio_sel),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PWDATA   (PWDATA),
        .PRDATA   (gpio_prdata),
        .PREADY   (gpio_pready),
        .PSLVERR  (),
        .gpio_out (gpio_out),
        .gpio_stat(32'b0)
    );

    // sfp_regs — dedicated register block for SerDes status and control
    // sfp_stat bit mapping (from sfp_loopback serdes_stat):
    //   [0]  ln0_signal_detect  [1]  ln0_rx_cdr_lock  [2]  ln0_k_lock
    //   [3]  ln0_word_align     [4]  ln0_pll_lock      [5]  ln0_ready
    //   [6]  ln0_prbs_lock      [7]  ln1_prbs_lock
    //   [8]  ln1_signal_detect  [9]  ln1_rx_cdr_lock  [10] ln1_k_lock
    //   [11] ln1_word_align     [12] ln1_pll_lock     [13] ln1_ready
    //   [14] ln0_rx_valid       [15] ln0_rx_fifo_empty
    //   [16] ln1_rx_valid       [17] ln1_rx_fifo_empty
    //   [18] ln0_tx_fifo_afull  [19] ln0_tx_fifo_full
    //   [20] ln1_tx_fifo_afull  [21] ln1_tx_fifo_full
    sfp_regs sfp_regs_inst (
        .pclk    (APBCLK),
        .presetn (APBRESET),
        .paddr   (PADDR[4:2]),
        .psel    (sfp_sel),
        .pwrite  (PWRITE),
        .penable (PENABLE),
        .pready  (sfp_pready),
        .pwdata  (PWDATA),
        .pstrb   (4'hF),
        .prdata  (sfp_prdata),
        .pslverr (),

        .stat_ln0_signal_detect_i  (sfp_stat[0]),
        .stat_ln0_rx_cdr_lock_i    (sfp_stat[1]),
        .stat_ln0_k_lock_i         (sfp_stat[2]),
        .stat_ln0_word_align_link_i(sfp_stat[3]),
        .stat_ln0_pll_lock_i       (sfp_stat[4]),
        .stat_ln0_ready_i          (sfp_stat[5]),
        .stat_ln0_prbs_lock_i      (sfp_stat[6]),
        .stat_ln0_rx_valid_i       (sfp_stat[14]),
        .stat_ln0_rx_fifo_empty_i  (sfp_stat[15]),
        .stat_ln0_tx_fifo_afull_i  (sfp_stat[18]),
        .stat_ln0_tx_fifo_full_i   (sfp_stat[19]),

        .stat_ln1_signal_detect_i  (sfp_stat[8]),
        .stat_ln1_rx_cdr_lock_i    (sfp_stat[9]),
        .stat_ln1_k_lock_i         (sfp_stat[10]),
        .stat_ln1_word_align_link_i(sfp_stat[11]),
        .stat_ln1_pll_lock_i       (sfp_stat[12]),
        .stat_ln1_ready_i          (sfp_stat[13]),
        .stat_ln1_prbs_lock_i      (sfp_stat[7]),
        .stat_ln1_rx_valid_i       (sfp_stat[16]),
        .stat_ln1_rx_fifo_empty_i  (sfp_stat[17]),
        .stat_ln1_tx_fifo_afull_i  (sfp_stat[20]),
        .stat_ln1_tx_fifo_full_i   (sfp_stat[21]),

        .ln0_rx_snap_i (ln0_rx_snap),
        .ln1_rx_snap_i (ln1_rx_snap),

        .ctrl_tx_mode_o (tx_mode),
        .tx_pattern_o   (tx_pattern)
    );

    // APB response mux
    assign PRDATA =
        sysinfo_sel ? sysinfo_prdata :
        gpio_sel    ? gpio_prdata    :
        sfp_sel     ? sfp_prdata     :
                      32'h00000000;

    assign PREADY =
        sysinfo_sel ? sysinfo_pready :
        gpio_sel    ? gpio_pready    :
        sfp_sel     ? sfp_pready     :
                      1'b1;

    assign PSLVERR = 1'b0;

endmodule
