//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.01
//IP Version: 1.0
//Part Number: GW5AST-LV138FPG676AC2/I1
//Device: GW5AST-138
//Device Version: B
//Created Time: Tue Apr  7 18:20:45 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    Gowin_PLL_ffc_MOD your_instance_name(
        .lock(lock), //output lock
        .clkout0(clkout0), //output clkout0
        .clkin(clkin), //input clkin
        .reset(reset), //input reset
        .icpsel(icpsel), //input [5:0] icpsel
        .lpfres(lpfres), //input [2:0] lpfres
        .lpfcap(lpfcap) //input [1:0] lpfcap
    );

//--------Copy end-------------------
