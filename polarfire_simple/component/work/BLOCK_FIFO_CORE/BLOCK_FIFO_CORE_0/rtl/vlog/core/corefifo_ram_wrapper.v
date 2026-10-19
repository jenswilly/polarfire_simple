// ********************************************************************/
// © 2026 Microchip Technology Inc. and its subsidiaries
//
// Subject to your compliance with the terms and conditions of the
// license agreement accompanying this software, you may use this
// Microchip software and any derivatives exclusively with Microchip
// products. You are responsible for complying with third party license
// terms applicable to your use of third party software (including open
// source software) that may accompany this Microchip software.
// SOFTWARE IS "AS IS." NO WARRANTIES, WHETHER EXPRESS, IMPLIED OR
// STATUTORY, APPLY TO THIS SOFTWARE, INCLUDING ANY IMPLIED WARRANTIES
// OF NON-INFRINGEMENT, MERCHANTABILITY, OR FITNESS FOR A PARTICULAR
// PURPOSE. IN NO EVENT WILL MICROCHIP BE LIABLE FOR ANY INDIRECT,
// SPECIAL, PUNITIVE, INCIDENTAL OR CONSEQUENTIAL LOSS, DAMAGE, COST OR
// EXPENSE OF ANY KIND WHATSOEVER RELATED TO THE SOFTWARE, HOWEVER
// CAUSED, EVEN IF MICROCHIP HAS BEEN ADVISED OF THE POSSIBILITY OR THE
// DAMAGES ARE FORESEEABLE. TO THE FULLEST EXTENT ALLOWED BY LAW,
// MICROCHIP'S TOTAL LIABILITY ON ALL CLAIMS RELATED TO THE SOFTWARE
// WILL NOT EXCEED AMOUNT OF FEES, IF ANY, YOU PAID DIRECTLY TO
// MICROCHIP FOR THIS SOFTWARE.
//
// *********************************************************************/

`timescale 1 ns/100 ps
module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_ram_wrapper(                                                                                                                              
W_DATA,                                                                                                                                                      
WD,                                                                                                                                                      
C_DIN,                                                                                                                                                      
W_ADDR,                                                                                                                                                      
WADDR,                                                                                                                                                      
C_ADDR,                                                                                                                                                      
W_EN,                                                                                                                                                        
C_WEN,                                                                                                                                                        
WEN,                                                                                                                                                        
WBYTE_EN,                                                                                                                                                        
R_EN,                                                                                                                                                        
REN,                                                                                                                                                        
A_ADDR_EN,                                                                                                                                                        
B_ADDR_EN,                                                                                                                                                        
A_BLK,                                                                                                                                                        
B_BLK,                                                                                                                                                        
R_DATA,                                                                                                                                                      
RD,                                                                                                                                                      
A_DOUT,                                                                                                                                                      
R_ADDR,                                                                                                                                                       
A_ADDR,                                                                                                                                                  
B_ADDR,                                                                                                                                                    
RADDR,                                                                                                                                                    
RESET_N,                                                                                                                                                     
ARST_N,                                                                                                                                                
RD_SRST_N,                                                                                                                                                
R_DATA_ARST,                                                                                                                                                    
R_DATA_ARST_N,                                                                                                                                                    
R_DATA_SRST_N,                                                                                                                                                     
R_ADDR_SRST_N,                                                                                                                                                
A_ADDR_SRST_N,                                                                                                                                               
B_ADDR_SRST_N,                                                                                                                                                    
R_ADDR_ARST_N,
A_DOUT_SRST_N,
B_DOUT_SRST_N,                                                                                                                                                    
CLK,                                                                                                                                        
BLK_EN,
R_ADDR_EN,                                                                                                                                                      
W_CLK,                                                                                                                                                    
WCLK,                                                                                                                                                    
SB_CORRECT,                                                                                                                                              
A_SB_CORRECT,                                                                                                                                              
B_SB_CORRECT,                                                                                                                                              
DB_DETECT,                                                                                                                                                     
A_DB_DETECT,                                                                                                                                                     
B_DB_DETECT,                                                                                                                                                     
R_CLK,                                                                                                                                                
RCLK,
C_CLK,
A_CLK,
B_CLK,
DATA_IN,    
DATA_OUT,   
INJECT_ERR_N,
WR_ADDR,     
RD_ADDR,     
RD_EN,       
WR_EN,       
WR_CLK,      
RD_CLK,
RD_PL_SRST_N,
BUSY_FB,     
SLEEP_N,     
RD_PL_ARST_N,
RD_PL_EN, 
ACCESS_BUSY                                                                                                                                                    
);                                                                                                                                                          
                                                                                                                                                            
                                                                                                                                                            
// --------------------------------------------------------------------------                                                                               
// PARAMETER Declaration                                                                                                                                    
// --------------------------------------------------------------------------                                                                               
parameter                RWIDTH        = 32;  // Read  port Data Width                                                                                      
parameter                WWIDTH        = 32;  // Write port Data Width                                                                                      
parameter                RDEPTH        = 128; // Read  port Data Depth                                                                                      
parameter                WDEPTH        = 128; // Write port Data Depth                                                                                      
parameter                SYNC          = 0;   // Synchronous or Asynchronous operation | 1 - Single Clock, 0 - Dual clock                                   
parameter                PIPE          = 1;   // Pipeline read data out                                                                                     
parameter                CTRL_TYPE     = 1;   // Controller only options | 1 - Controller Only, 2 - RAM1Kx18, 3 - RAM64x18
parameter                SYNC_RESET    = 0;   // Synchronous or Asynchronous RESET | 1 - Synchronous reset, 0 - Asynchronous reset
parameter                RAM_OPT       = 0;   // |  0 -High Speed , 1 - Low Power
parameter                WDEPTH_CAL    = 8;
parameter                RDEPTH_CAL    = 8;
// --------------------------------------------------------------------------
// I/O Declaration
// --------------------------------------------------------------------------
input [WWIDTH - 1 : 0]   W_DATA;  
input [WWIDTH - 1 : 0]   WD;         // RTG4 : LSRAM
input [WWIDTH - 1 : 0]   C_DIN;      // RTG4 : uSRAM
input [(WDEPTH - 1) : 0] W_ADDR;  
input [(WDEPTH - 1) : 0] WADDR;  
input [(WDEPTH - 1) : 0] C_ADDR;  
input                    W_EN;    
input                    C_WEN;    
input                    WEN;    
input                    WBYTE_EN;    
input                    R_EN;    
input                    REN;    
input                    A_ADDR_EN;    
input                    B_ADDR_EN;    
input                    A_BLK;                                  
input                    B_BLK;                                  
output [RWIDTH - 1 : 0]  R_DATA;    // PF/PFSoC                  
output [RWIDTH - 1 : 0]  RD;        // RTG4 : LSRAM              
output [RWIDTH - 1 : 0]  A_DOUT;    // RTG4 : uSRAM              
input [(RDEPTH - 1) : 0] R_ADDR;                                 
input [(RDEPTH - 1) : 0] A_ADDR;                                 
input [(RDEPTH - 1) : 0] B_ADDR;                                   
input [(RDEPTH - 1) : 0] RADDR;                                  
input                    RESET_N;                                
input                    ARST_N;                                 
input                    RD_SRST_N;                                 
input                    R_DATA_ARST;                          
input                    R_DATA_ARST_N;                          
input                    R_DATA_SRST_N;                          
input                    R_ADDR_SRST_N;                          
input                    A_ADDR_SRST_N;                          
input                    B_ADDR_SRST_N;                            
input                    R_ADDR_ARST_N;                            
input                    A_DOUT_SRST_N;                            
input                    B_DOUT_SRST_N;                            
input                    W_CLK;                                  
input                    WCLK; 
input                    R_CLK; 
input                    RCLK; 
input                    C_CLK; 
input                    A_CLK; 
input                    B_CLK; 
output                   SB_CORRECT; 
output                   A_SB_CORRECT; 
output                   B_SB_CORRECT; 
output                   DB_DETECT;
output                   A_DB_DETECT;
output                   B_DB_DETECT;
input                    CLK;
input                    BLK_EN;
input                    R_ADDR_EN;
input  [(WWIDTH - 1):0]  DATA_IN      ;    
output [(RWIDTH - 1):0]  DATA_OUT     ;   
input  [7:0]             INJECT_ERR_N ;
input  [WDEPTH_CAL : 0]  WR_ADDR      ;     
input  [RDEPTH_CAL : 0]  RD_ADDR      ;     
input                    RD_EN        ;       
input                    WR_EN        ;       
input                    WR_CLK       ;      
input                    RD_CLK       ;
input                    RD_PL_SRST_N ;
input                    BUSY_FB      ;     
input                    SLEEP_N      ;     
input                    RD_PL_ARST_N ;
input                    RD_PL_EN     ; 
output                   ACCESS_BUSY  ;


wire [RWIDTH - 1 : 0]    B_DOUT;
wire                     C_BLK;
wire                     R_DATA_EN;
wire                     A_DOUT_EN;
wire                     B_DOUT_EN;


assign C_BLK         = 1;
assign R_DATA_EN     = 1;
assign A_DOUT_EN     = 1;
assign B_DOUT_EN     = 1;


BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO_ram_wrapper  g4_g5_g6_ram_wrapper_inst (.*);

endmodule
