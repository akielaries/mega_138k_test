//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.12.01 
//Created Time: 2026-03-08 14:29:10
create_clock -name hclk -period 20 -waveform {0 10} [get_ports {HCLK}]
create_clock -name swd_clk -period 200 -waveform {0 100} [get_ports {JTAG_9_SWDCLK}]

create_clock -name ddr3_mem_clk -period 5 -waveform {0 2.5} [get_pins {u_Gowin_PLL/u_pll/PLL_inst/CLKOUT2}]
create_clock -name ddr3_sys_clk -period 20 -waveform {0 10} [get_pins {Cortex_M1_instance/u_GowinCM1AhbExtWrapper/u_GowinCM1AhbExt/u_ahb_ddr3/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

// SFP+ SerDes clocks — 156.25 MHz recovered from 10.3125G link (period ~6.4 ns)
create_clock -name sfp_ln0_tx_clk -period 6.4 -waveform {0 3.2} [get_nets {sfp_inst/ln0_tx_pcs_clk}]
create_clock -name sfp_ln0_rx_clk -period 6.4 -waveform {0 3.2} [get_nets {sfp_inst/ln0_rx_pcs_clk}]
create_clock -name sfp_ln1_tx_clk -period 6.4 -waveform {0 3.2} [get_nets {sfp_inst/ln1_tx_pcs_clk}]
create_clock -name sfp_ln1_rx_clk -period 6.4 -waveform {0 3.2} [get_nets {sfp_inst/ln1_rx_pcs_clk}]

set_clock_groups -exclusive -group [get_clocks {hclk}] -group [get_clocks {swd_clk}] -group [get_clocks {ddr3_sys_clk}] -group [get_clocks {ddr3_mem_clk}] -group [get_clocks {sfp_ln0_tx_clk}] -group [get_clocks {sfp_ln0_rx_clk}] -group [get_clocks {sfp_ln1_tx_clk}] -group [get_clocks {sfp_ln1_rx_clk}]
