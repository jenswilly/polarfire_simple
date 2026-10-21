//////////////////////////////////////////////////////////////////////
// Created by SmartDesign Mon Oct 19 13:44:17 2026
// Version: 2026.1 2026.1.0.17
//////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps

//////////////////////////////////////////////////////////////////////
// Component Description (Tcl) 
//////////////////////////////////////////////////////////////////////
/*
# Exporting Component Description of BLOCK_FIFO_CORE to TCL
# Family: PolarFireSoC
# Part Number: MPFS095T-1FCSG325E
# Create and Configure the core component BLOCK_FIFO_CORE
create_and_configure_core -core_vlnv {Actel:DirectCore:COREFIFO:4.0.139} -component_name {BLOCK_FIFO_CORE} -params {\
"AE_DYN_EN:false"  \
"AE_STATIC_EN:false"  \
"AEVAL:4"  \
"AF_DYN_EN:false"  \
"AF_STATIC_EN:false"  \
"AFVAL:1020"  \
"CTRL_TYPE:2"  \
"ECC:0"  \
"ESTOP:true"  \
"FSTOP:true"  \
"FWFT:true"  \
"LEGACY:1"  \
"NUM_STAGES:2"  \
"OVERFLOW_EN:false"  \
"PIPE:1"  \
"PREFETCH:false"  \
"RAM_OPT:0"  \
"RDCNT_EN:false"  \
"RDEPTH:512"  \
"RE_POLARITY:0"  \
"READ_DVALID:false"  \
"RWIDTH:80"  \
"SYNC:1"  \
"SYNC_RESET:1"  \
"UNDERFLOW_EN:false"  \
"WDEPTH:512"  \
"WE_POLARITY:0"  \
"WRCNT_EN:false"  \
"WRITE_ACK:false"  \
"WWIDTH:80"   }
# Exporting Component Description of BLOCK_FIFO_CORE to TCL done
*/

// BLOCK_FIFO_CORE
module BLOCK_FIFO_CORE(
    // Inputs
    CLK,
    DATA,
    RE,
    RESET_N,
    WE,
    // Outputs
    EMPTY,
    FULL,
    Q
);

//--------------------------------------------------------------------
// Input
//--------------------------------------------------------------------
input         CLK;
input  [79:0] DATA;
input         RE;
input         RESET_N;
input         WE;
//--------------------------------------------------------------------
// Output
//--------------------------------------------------------------------
output        EMPTY;
output        FULL;
output [79:0] Q;
//--------------------------------------------------------------------
// Nets
//--------------------------------------------------------------------
wire          CLK;
wire   [79:0] DATA;
wire          EMPTY_net_0;
wire          FULL_net_0;
wire   [79:0] Q_net_0;
wire          RE;
wire          RESET_N;
wire          WE;
wire   [79:0] Q_net_1;
wire          FULL_net_1;
wire          EMPTY_net_1;
//--------------------------------------------------------------------
// TiedOff Nets
//--------------------------------------------------------------------
wire          GND_net;
wire   [8:0]  AF_THRSHLD_const_net_0;
wire   [8:0]  AE_THRSHLD_const_net_0;
wire   [79:0] MEMRD_const_net_0;
//--------------------------------------------------------------------
// Constant assignments
//--------------------------------------------------------------------
assign GND_net                = 1'b0;
assign AF_THRSHLD_const_net_0 = 9'h000;
assign AE_THRSHLD_const_net_0 = 9'h000;
assign MEMRD_const_net_0      = 80'h00000000000000000000;
//--------------------------------------------------------------------
// Top level output port assignments
//--------------------------------------------------------------------
assign Q_net_1     = Q_net_0;
assign Q[79:0]     = Q_net_1;
assign FULL_net_1  = FULL_net_0;
assign FULL        = FULL_net_1;
assign EMPTY_net_1 = EMPTY_net_0;
assign EMPTY       = EMPTY_net_1;
//--------------------------------------------------------------------
// Component instances
//--------------------------------------------------------------------
//--------BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO   -   Actel:DirectCore:COREFIFO:4.0.139
BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO #( 
        .AE_DYN_EN    ( 0 ),
        .AE_STATIC_EN ( 0 ),
        .AEVAL        ( 4 ),
        .AF_DYN_EN    ( 0 ),
        .AF_STATIC_EN ( 0 ),
        .AFVAL        ( 1020 ),
        .CTRL_TYPE    ( 2 ),
        .ECC          ( 0 ),
        .ESTOP        ( 1 ),
        .FAMILY       ( 27 ),
        .FSTOP        ( 1 ),
        .FWFT         ( 1 ),
        .LEGACY       ( 1 ),
        .NUM_STAGES   ( 2 ),
        .OVERFLOW_EN  ( 0 ),
        .PIPE         ( 1 ),
        .PREFETCH     ( 0 ),
        .RAM_OPT      ( 0 ),
        .RDCNT_EN     ( 0 ),
        .RDEPTH       ( 512 ),
        .RE_POLARITY  ( 0 ),
        .READ_DVALID  ( 0 ),
        .RWIDTH       ( 80 ),
        .SYNC         ( 1 ),
        .SYNC_RESET   ( 1 ),
        .UNDERFLOW_EN ( 0 ),
        .WDEPTH       ( 512 ),
        .WE_POLARITY  ( 0 ),
        .WRCNT_EN     ( 0 ),
        .WRITE_ACK    ( 0 ),
        .WWIDTH       ( 80 ) )
BLOCK_FIFO_CORE_0(
        // Inputs
        .CLK        ( CLK ),
        .WCLOCK     ( GND_net ), // tied to 1'b0 from definition
        .RCLOCK     ( GND_net ), // tied to 1'b0 from definition
        .RESET_N    ( RESET_N ),
        .WRESET_N   ( GND_net ), // tied to 1'b0 from definition
        .RRESET_N   ( GND_net ), // tied to 1'b0 from definition
        .DATA       ( DATA ),
        .WE         ( WE ),
        .RE         ( RE ),
        .AF_THRSHLD ( AF_THRSHLD_const_net_0 ), // tied to 9'h000 from definition
        .AE_THRSHLD ( AE_THRSHLD_const_net_0 ), // tied to 9'h000 from definition
        .MEMRD      ( MEMRD_const_net_0 ), // tied to 80'h00000000000000000000 from definition
        // Outputs
        .Q          ( Q_net_0 ),
        .FULL       ( FULL_net_0 ),
        .EMPTY      ( EMPTY_net_0 ),
        .AFULL      (  ),
        .AEMPTY     (  ),
        .OVERFLOW   (  ),
        .UNDERFLOW  (  ),
        .WACK       (  ),
        .DVLD       (  ),
        .WRCNT      (  ),
        .RDCNT      (  ),
        .MEMWE      (  ),
        .MEMRE      (  ),
        .MEMWADDR   (  ),
        .MEMRADDR   (  ),
        .MEMWD      (  ),
        .SB_CORRECT (  ),
        .DB_DETECT  (  ) 
        );


endmodule
