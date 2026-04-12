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

// RGMII Ethernet clocks
// gtx_clk_125: 125 MHz TX clock from PLL (period 8 ns)
// gtx_clk_125: 125 MHz TX clock from PLL clkout0
// rgmii_rxc: 125 MHz from PLL clkout3 (90 deg phase offset) -- replaces PHY-supplied RXC on C23
create_clock -name gtx_clk_125 -period 8  -waveform {0 4}  [get_pins {u_Gowin_PLL/u_pll/PLL_inst/CLKOUT0}]
create_clock -name rgmii_rxc   -period 8  -waveform {0 4}  [get_pins {u_Gowin_PLL/u_pll/PLL_inst/CLKOUT3}]

// MultiFlex TX engine clock: 200 MHz from PLL_ffc clkout0 (ODIV0_SEL=4, VCO=800 MHz)
// routed through CLKDIV (DIV_MODE=1, pass-through) onto HCLK spine
// constrain both the raw PLL net and the CLKDIV output so synthesis and PnR
// both see the frequency; the tool propagates the constraint through CLKDIV
create_clock -name mfx_clk_fast -period 5 -waveform {0 2.5} [get_nets {multiflex_clk_fast}]
create_clock -name mfx_clk      -period 5 -waveform {0 2.5} [get_nets {multiflex_clk}]

set_clock_groups -exclusive -group [get_clocks {hclk}] -group [get_clocks {swd_clk}] -group [get_clocks {ddr3_sys_clk}] -group [get_clocks {ddr3_mem_clk}] -group [get_clocks {sfp_ln0_tx_clk}] -group [get_clocks {sfp_ln0_rx_clk}] -group [get_clocks {sfp_ln1_tx_clk}] -group [get_clocks {sfp_ln1_rx_clk}] -group [get_clocks {gtx_clk_125}] -group [get_clocks {rgmii_rxc}] -group [get_clocks {mfx_clk_fast}] -group [get_clocks {mfx_clk}]

// rgmii_rxc -> gtx_clk_125 paths inside the Gowin triple-speed MAC IP are
// internally synchronized; the tool sees a combinational arc between the two
// recovered clocks but there is no valid timing relationship to check.
set_false_path -from [get_clocks {rgmii_rxc}] -to [get_clocks {gtx_clk_125}]
