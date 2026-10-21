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

`timescale 1ns / 100ps
module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO (
                  // Clocks and Reset
                  CLK,                   // Single Clock for synchronous operation
                  WCLOCK,                // write Clock
                  RCLOCK,                // Read Clock
                  RESET_N,               // Reset active low
				  WRESET_N,
				  RRESET_N,
                  // Input Data Bus and Control ports
                  DATA,                  // Input Write data
                  WE,                    // Write Enable
                  RE,                    // Read Enable
                  // Output Data bus
                  Q,                     // Output Read data
                  // Status Flags
                  FULL,                  // Full flag
                  EMPTY,                 // Empty flag
                  AFULL,                 // Almost Full flag
                  AF_THRSHLD,            // Almost Full Dynamic flag
                  AEMPTY,                // Almost Empty flag
                  AE_THRSHLD,            // Almost Empty Dynamic flag
                  OVERFLOW,              // Overflow indicates write failure
                  UNDERFLOW,             // Underflow indicates read failure
                  WACK,                  // Write Acknowledge
                  DVLD,                  // Read Data valid
                  WRCNT,                 // No.of remaining elements in write domain
                  RDCNT,                 // No.of remaining elements in read domain
                  // For external memory
                  MEMWE,                 // Memory Write enable
                  MEMRE,                 // Memory Read enable
                  MEMWADDR,              // Memory Write Address
                  MEMRADDR,              // Memory Read Address
                  MEMWD,                 // Memory Write Data
                  MEMRD,                 // Memory Read Data
                  SB_CORRECT,            // One-bit correct flag
                  DB_DETECT              // Detect flag
                  );


   // --------------------------------------------------------------------------
   // PARAMETER Declaration
   // --------------------------------------------------------------------------
   parameter                FAMILY        = 26;
   parameter                LEGACY        = 1;
   parameter                SYNC          = 0;   // Synchronous or Asynchronous operation | 1 - Single Clock, 0 - Dual clock
   //parameter                RCLK_EDGE     = 1;   // Read  Clock Edge | 1 - Posedge, 0 - Negedge		// commented in v3.0
   //parameter                WCLK_EDGE     = 1;   // Write Clock Edge | 1 - Posedge, 0 - Negedge       // commented in v3.0
   parameter                RE_POLARITY   = 0;   // Read  Enable Clock Edge | 1 - Active Low, 0 - Active High
   parameter                WE_POLARITY   = 0;   // Write Enable Clock Edge | 1 - Active Low, 0 - Active High
   parameter                RWIDTH        = 72;  // Read  port Data Width
   parameter                WWIDTH        = 72;  // Write port Data Width
   parameter                RDEPTH        = 8; // Read  port Data Depth
   parameter                WDEPTH        = 8; // Write port Data Depth
   parameter                READ_DVALID   = 1;   // Read Data Valid | 0 - Disable , 1 - Enable Read data valid generation
   parameter                WRITE_ACK     = 1;   // Write Data Ack  | 0 - Disable , 1 - Enable Write data ack generation
   parameter                CTRL_TYPE     = 2;   // Controller only options | 1 - Controller Only, 2 - RAM1Kx18, 3 - RAM64x18
   parameter                ESTOP         = 1;   // 0 - Allow Reads when Empty, 1 - Disable Reads when Empty
   parameter                FSTOP         = 1;   // 0 - Allow Writes when Full,  1 - Disable Writes when Full
   parameter                AE_STATIC_EN  = 1;   // Almost Empty Threshold Enable/Disable Static values
                                                 // 0 - Disable values, 1 - Enable Static values 
   parameter                AF_STATIC_EN  = 1;   // Almost Full Threshold Enable/Disable Static values
                                                 // 0 - Disable values, 1 - Enable Static values
   parameter                AE_DYN_EN     = 0;   // Almost Empty Dynamic Threshold Enable/Disable dynamic values
                                                 // 0 - Disable dynamic values, 1 - Enable dynamic values 
   parameter                AF_DYN_EN     = 0;   // Almost Full Dynamic Threshold Enable/Disable dynamic values
                                                 // 0 - Disable dynamic values, 1 - Enable dynamic values
   parameter                AEVAL         = 2;   // Almost Empty Threshold assert value
   parameter                AFVAL         = 6;   // Almost Full  Threshold assert value
   parameter                PIPE          = 1;   // Pipeline read data out
   parameter                PREFETCH      = 0;   // Prefetching of Read data | 0 - Disable Pre-fetching, 1 - Enable Pre-fetching only if PIPE=1
   parameter                FWFT          = 0;   // FWFT of Read data | 0 - Disable FWFT, 1 - Enable FWFT only if PIPE=1
   parameter                ECC           = 0;   // ECC | 0 - ECC Disable, 1 - Pipelined ECC, 2 - Non-pipelined ECC
  // parameter                RESET_POLARITY = 0;  // Polarity of Reset | 0 - Active Low, 1 - Active High// commented in v3.0
   parameter                OVERFLOW_EN    = 0;  // Overflow Enable/Disable | 0 - Disable, 1 - Enable
   parameter                UNDERFLOW_EN   = 0;  // Underflow Enable/Disable | 0 - Disable, 1 - Enable
   parameter                WRCNT_EN       = 0;  // Write Count Enable/Disable | 0 - Disable, 1 - Enable
   parameter                RDCNT_EN       = 0;  // Read Count Enable/Disable | 0 - Disable, 1 - Enable
   
   parameter                NUM_STAGES       = 2; // To select number of synchronizer stages.
   
   
   ////Added in v3.0
   parameter				SYNC_RESET		= 1;//To select reset type asynch/sync reset.|0-async reset, 1-sync reset
   parameter				RAM_OPT			= 0;//RAM optimization for high speed or low power.|0-High Speed,1-Low power
   //parameter				DIE_SIZE		= 30; //added in v3.0
 //------
 
 
   // **************************************************************************
   // Function Declaration
   // **************************************************************************
   function [31:0] ceil_log2;
      input integer x;
      integer tmp, res;
      begin
         tmp = 1;
         res = 0;
         while(tmp < x) begin
            tmp = tmp * 2;
            res = res + 1;
         end
         ceil_log2 = res;
      end
   endfunction // ceil_log2

  function [31:0] ceil_log2t;
      input integer x;
      integer tmp, res;
      begin
         tmp = 1;
         res = 0;
	 if(x == 1) begin
           ceil_log2t = 1;
	 end
	 else begin
           while(tmp < x) begin
              tmp = tmp * 2;
              res = res + 1;
           end
	   ceil_log2t = res;
         end
      end
   endfunction // ceil_log2t
   // **************************************************************************

   // --------------------------------------------------------------------------
   // Local parameter
   // --------------------------------------------------------------------------
   localparam WMSB_DEPTH      = (ceil_log2(WDEPTH));
   localparam RMSB_DEPTH      = (ceil_log2(RDEPTH)); 
   localparam WDEPTH_CAL      = (WDEPTH == 1) ? (ceil_log2(WDEPTH))  : (ceil_log2(WDEPTH)-1); 
   localparam RDEPTH_CAL      = (RDEPTH == 1) ? (ceil_log2(RDEPTH))  : (ceil_log2(RDEPTH)-1); 
   localparam RESET_POLARITY  = 0;  // Polarity of Reset | 0 - Active Low, ----added in v3.0
   localparam RCLK_EDGE  = 1;  // Read  Clock Edge | 1 - Posedge, 	----added in v3.0
   localparam WCLK_EDGE  = 1;  // Write  Clock Edge | 1 - Posedge,	----added in v3.0
   //localparam SYNC_RESET      = (FAMILY == 25) ? 1 : 0; // 0 = async mode, 1 = sync mode
   localparam RAM_SEL         = (CTRL_TYPE  == 'd2) ? 'd2: 'd3; 
   
   
   //localparam SYNC_RESET      = (RESET_TYPE == 1) ? 1 : 0; // 0 = async mode, 1 = sync mode

   // --------------------------------------------------------------------------
   // I/O Declaration
   // --------------------------------------------------------------------------
   
   //--------
   // Inputs
   //--------

   // Clocks and Reset
   input                            CLK;   
   input                            WCLOCK;
   input                            RCLOCK;
   input                            RESET_N;
   input							WRESET_N;//Added in v3.0
   input							RRESET_N;//Added in v3.0
   // Input Data Bus and Control ports
   input [WWIDTH - 1 : 0]           DATA;
   input                            WE;
   input                            RE;
   input [RWIDTH - 1 : 0]           MEMRD;

   output                            SB_CORRECT;
   output                            DB_DETECT;

   //---------
   // Outputs
   //---------

   // Output Data bus
   output [RWIDTH - 1 : 0]          Q;
   // Output Status Flags
   output                           FULL;
   output                           EMPTY;
   output                           AFULL;
   input  [(ceil_log2(WDEPTH))-1 : 0] AF_THRSHLD;
   output                           AEMPTY;
   input  [(ceil_log2(RDEPTH))-1 : 0] AE_THRSHLD;
   output                           OVERFLOW;
   output                           UNDERFLOW;
   output                           WACK;
   output                           DVLD;
   output [(ceil_log2(WDEPTH)) : 0] WRCNT;
   output [(ceil_log2(RDEPTH)) : 0] RDCNT;
   // Outputs For external memory
   output                           MEMWE;
   output                           MEMRE;
   output [WDEPTH_CAL : 0]          MEMWADDR;
   output [RDEPTH_CAL : 0]          MEMRADDR;
   output [WWIDTH - 1 : 0]          MEMWD;

   // --------------------------------------------------------------------------
   // Internal signals
   // --------------------------------------------------------------------------
   wire                             EMPTY1;
   wire                             AEMPTY1;
   wire                             EMPTY2;
   wire                             AEMPTY2;
   wire                             fifo_rd_en;
   wire                             fifo_re_in;   
   wire [WDEPTH_CAL : 0]            fifo_MEMWADDR;
   wire [RDEPTH_CAL : 0]            fifo_MEMRADDR;
   wire [RDEPTH_CAL : 0]            pf_MEMRADDR;
   wire [RDEPTH_CAL : 0]            fwft_MEMRADDR;
   wire [RDEPTH_CAL : 0]            ram_raddr;
   wire                             fifo_MEMWE;
   wire                             fifo_MEMRE;
   wire                             fifo_MEMRE_int;
   wire [RWIDTH - 1 : 0]            pf_Q;
   wire [RWIDTH - 1 : 0]            fwft_Q;
   wire [RWIDTH - 1 : 0]            int_MEMRD;
   wire [RWIDTH - 1 : 0]            int_MEMRD_fwft_pipe1;
   wire [RWIDTH - 1 : 0]            int_MEMRD_fwft_pipe2;
   wire [RWIDTH - 1 : 0]            int_MEMRD_fwft_pipe3;
   wire [RWIDTH - 1 : 0]            int_MEMRD_pipe0;
   wire [RWIDTH - 1 : 0]            int_MEMRD_pipe1;
   wire [RWIDTH - 1 : 0]            int_MEMRD_pipe2;
   wire [RWIDTH - 1 : 0]            mem_pf_RD;
   wire [RWIDTH - 1 : 0]            ext_MEMRD;
   wire [RWIDTH - 1 : 0]            ext_MEMRD_fwft;
    // ext_MEMRD_fwft_pipe2 removed
   wire [RWIDTH - 1 : 0]            ext_MEMRD_pipe0;
   wire [RWIDTH - 1 : 0]            ext_MEMRD_pipe1;
   wire [RWIDTH - 1 : 0]            ext_MEMRD_pipe2;
   wire                             RE_pol;
   wire [RWIDTH - 1 : 0]            RDATA_int; 
   //reg  [RWIDTH - 1 : 0]            RDATA_int_ram_pf_pfs_rtg4;  
   reg  [RWIDTH - 1 : 0]            RDATA_int_ram_gen_3_4_5;
   reg  [RWIDTH - 1 : 0]            RDATA_int_ram_gen_6;
   reg  [RWIDTH - 1 : 0]            R_DATA;  
   reg  [RWIDTH - 1 : 0]            RD;  
   reg  [RWIDTH - 1 : 0]            A_DOUT;  
   wire                             re_pulse; 
   wire                             re_pulse_pre; 
   wire                             aresetn;
   wire                             sresetn;//uncommented in v3.0
   wire                             DVLD_async;
   wire                             DVLD_scntr;   // driven by fifo_corefifo_sync_scntr (SYNC=1, RDEPTH==WDEPTH, ESTOP==1, FSTOP==1)
   wire                             DVLD_sync;    // driven by U_corefifo_sync (SYNC=1, variable aspect ratio or ESTOP/FSTOP!=1)
   wire                             fwft_dvld;
   wire                             fwft_reg_valid;   
   wire                             pf_dvld;
   wire                             pos_rclk;
   wire                             pos_wclk;
   wire                             SB_CORRECT;
   wire                             DB_DETECT;
   wire                             A_SB_CORRECT;
   wire                             A_DB_DETECT;
   wire                             B_SB_CORRECT;
   wire                             B_DB_DETECT;
   wire                             W_SB_CORRECT;  
   wire                             W_DB_DETECT;   
   reg                              reg_valid;
   reg                              re_set;
   reg                              re_set_d1;
   reg                              re_set_d2;
   reg [RWIDTH - 1 : 0]             RDATA_r;  
   reg [RWIDTH - 1 : 0]             RDATA_r1;  
   reg [RWIDTH - 1 : 0]             RDATA_r_pre;  
   reg [RWIDTH - 1 : 0]             RDATA_ext_r;  
   reg [RWIDTH - 1 : 0]             RDATA_ext_r1;  
   reg                              REN_d1;
   reg                              REN_d2;
   reg                              re_pulse_d1;
   reg                              re_pulse_d2;
   reg                              RE_d1 ;
   reg                              RE_d2 ;
   reg [RWIDTH - 1 : 0]             fwft_Q_r;
   reg [RWIDTH - 1 : 0]             reg_RD;
   reg                              AEMPTY1_r;
   reg                              AEMPTY1_r1;
   // Jul 1 : For ECC
   reg [RWIDTH - 1 : 0]             RDATA_r2;   
   reg                              RE_d3 ;
   reg                              REN_d3;
   reg                              re_pulse_d3;
   wire [RWIDTH - 1 : 0]            int_MEMRD_pipe1_ecc1;
   wire [RWIDTH - 1 : 0]            int_MEMRD_pipe2_ecc1;
   reg                              DVLD_async_ecc;
   reg                              DVLD_sync_ecc;
   reg                              DVLD_scntr_ecc;
   
   reg  [RDEPTH_CAL : 0]            ram_raddr_reg;
   reg  [RWIDTH - 1 : 0]            RDATA_int_temp;   
   
   
   /*reg reset_reg;
   reg reset_reg1;*/
   wire re_p;
   wire we_p;
   
   wire reset_rclk;
   wire reset_wclk;
   wire reset_sync_r;
   wire reset_sync_w;

   wire aresetn_wclk;
   wire sresetn_wclk; 
   wire aresetn_rclk;   
   wire sresetn_rclk; 
   
   wire neg_reset;
   wire neg_wreset;
   wire neg_rreset;

   // --------------------------------------------------------------------------
   // ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
   // ||                                                                      ||
   // ||                     Start - of - Code                                ||
   // ||                                                                      ||
   // ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
   // --------------------------------------------------------------------------
   
   // --------------------------------------------------------------------------
   // clocks and enables
   // --------------------------------------------------------------------------
   generate
      if(RCLK_EDGE == 1) begin
         assign pos_rclk  = SYNC ? CLK : RCLOCK;  
      end
   endgenerate
   generate
      if(RCLK_EDGE == 0) begin
         assign pos_rclk  = SYNC ? ~CLK :  ~RCLOCK; 
      end
   endgenerate
   generate
      if(WCLK_EDGE == 1) begin
         assign pos_wclk  = SYNC ? CLK :  WCLOCK;
      end
   endgenerate
   generate
      if(WCLK_EDGE == 0) begin
         assign pos_wclk  = SYNC ? ~CLK :  ~WCLOCK;
      end
   endgenerate

   // --------------------------------------------------------------------------
   // resets
   // --------------------------------------------------------------------------
   assign neg_reset = (RESET_POLARITY == 1) ? ~RESET_N : RESET_N;//  uncommented in v3.0
   
   assign neg_wreset = (RESET_POLARITY == 1) ? ~WRESET_N : WRESET_N;//  added  in v3.0
   assign neg_rreset = (RESET_POLARITY == 1) ? ~RRESET_N : RRESET_N;//  added in v3.0
   
  
/*    generate
	  if(SYNC == 1)
		begin
			assign aresetn   = (SYNC_RESET == 1) ? 1'b1  : neg_reset;
			assign sresetn   = (SYNC_RESET == 1) ? neg_reset : 1'b1;  
		end
	endgenerate

   generate
	  if(SYNC == 0)
		begin
			assign w_aresetn   = (SYNC_RESET == 1) ? 1'b1 : neg_wreset ;
			assign w_sresetn   = (SYNC_RESET == 1) ? neg_wreset : 1'b1 ;
			assign r_aresetn   = (SYNC_RESET == 1) ? 1'b1 : neg_rreset;
			assign r_sresetn   = (SYNC_RESET == 1) ? neg_rreset : 1'b1 ; 			
		end
	endgenerate */
	 

			assign aresetn_wclk   = (SYNC_RESET == 1) ? 1'b1  : (SYNC == 1) ? neg_reset : neg_wreset ;
			assign sresetn_wclk   = (SYNC_RESET == 0) ? 1'b1  : (SYNC == 1) ? neg_reset : neg_wreset ;
			assign aresetn_rclk   = (SYNC_RESET == 1) ? 1'b1  : (SYNC == 1) ? neg_reset : neg_rreset;
			assign sresetn_rclk   = (SYNC_RESET == 0) ? 1'b1  : (SYNC == 1) ? neg_reset : neg_rreset ; 

	generate
	  if(SYNC == 1)
	    begin
			//assign aresetn   	  = (SYNC_RESET == 1) ? 1'b1 : neg_reset;
			//assign sresetn   	  = (SYNC_RESET == 1) ? neg_reset : 1'b1;
			assign aresetn   	  = aresetn_wclk;
			assign sresetn   	  = sresetn_wclk;			
		end	
	endgenerate			
/* 	generate
	  if(SYNC == 0)
	    begin
			assign aresetn_wclk   = (SYNC_RESET == 1) ? 1'b1 : neg_wreset ;
			assign sresetn_wclk   = (SYNC_RESET == 0) ? 1'b1 : neg_wreset ;
			assign aresetn_rclk   = (SYNC_RESET == 1) ? 1'b1 : neg_rreset;
			assign sresetn_rclk   = (SYNC_RESET == 0) ? 1'b1 : neg_rreset ;
		end
	  else
	    begin
		   assign aresetn   	  = (SYNC_RESET == 1) ? 1'b1 : neg_reset;
		   assign sresetn   	  = (SYNC_RESET == 1) ? neg_reset : 1'b1;
	    end
	endgenerate
		 */
/*  generate
      if(SYNC == 0) begin   
 BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_resetSync # (
                                  .NUM_STAGES (NUM_STAGES)
								  )
								  
		          w_corefifo_resetSync (
				                       .clk         (pos_wclk ),
									   .reset       (aresetn  ),
									   .reset_out   (reset_sync_w)
									   );
									

 BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_resetSync # (
                                  .NUM_STAGES (NUM_STAGES)
								  )
								  
		          r_corefifo_resetSync (
				                       .clk         (pos_rclk ),
									   .reset       (aresetn  ),
									   .reset_out   (reset_sync_r)
									   );		

  end
  endgenerate	 */	



									  
//-----------------------------------------------------------
//Resets 
//-----------------------------------------------------------
/*  generate
      if(SYNC == 0) begin
         assign reset_rclk  =(SYNC_RESET == 1) ? r_sresetn : r_aresetn;
         assign reset_wclk  =(SYNC_RESET == 1) ? w_sresetn : w_aresetn;
      end
   endgenerate
   
   
  generate
      if(SYNC == 1) begin
         assign reset_rclk  = (SYNC_RESET == 1) ? sresetn : aresetn;
         assign reset_wclk  = (SYNC_RESET == 1) ? sresetn : aresetn;
      end
   endgenerate
    */

         assign re_p  = RE_POLARITY  ? (~RE) : (RE);
         assign we_p  = WE_POLARITY  ? (~WE) : (WE);

/* synthesis translate_off */
always @(posedge pos_wclk)	 begin
	if(we_p & FULL)	
		$display("time:%t --> FAIL: Writing when FIFO is full",$time)	;		
end	


always @(posedge pos_rclk)	begin
	if(re_p & EMPTY) 
		$display("time:%t --> FAIL: Reading when FIFO is Empty",$time);		
	end

/* synthesis translate_on */

   // --------------------------------------------------------------------------
   // Generate top-level read data output
   // --------------------------------------------------------------------------         
   generate
      if(FWFT == 0 && PREFETCH == 0) begin
         assign Q   = mem_pf_RD;
      end
   endgenerate

   generate
      if(FWFT == 1 && PREFETCH == 0 && PIPE != 0) begin
         //assign Q   = (fwft_dvld & (RE_pol | fwft_reg_valid)) ? fwft_Q : fwft_Q_r;
         //assign Q   = (EMPTY == 1) ? fwft_Q_r : fwft_Q; // added by  mahesh
         assign Q   =  fwft_Q; // added by  mahesh
      end
   endgenerate

   generate
      if(FWFT == 0 && PREFETCH == 1 && PIPE != 0) begin
         assign Q   = RE_pol ? fwft_Q : fwft_Q_r; 
      end
   endgenerate
   
   // --------------------------------------------------------------------------
   // Generate FIFO flags
   // --------------------------------------------------------------------------         
   assign EMPTY  = (FWFT || PREFETCH) ? EMPTY2 : EMPTY1;

   generate
      if((FWFT == 1 || PREFETCH == 1) && PIPE != 0) begin
         assign AEMPTY = AEMPTY2;  
      end
   endgenerate
   generate
      if(FWFT == 0 && PREFETCH == 0) begin
         assign AEMPTY = AEMPTY1;
      end
   endgenerate
 
   always @(posedge pos_rclk or negedge aresetn_rclk)
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           AEMPTY1_r  <= 'h0;
           AEMPTY1_r1 <= 'h0;
        end
        else begin
           AEMPTY1_r  <= AEMPTY1;
           AEMPTY1_r1 <= AEMPTY1_r;
        end
     end

   // Jul 1 : For ECC
   always @(posedge pos_rclk or negedge aresetn_rclk)
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           DVLD_async_ecc  <= 'h0;
           DVLD_sync_ecc   <= 'h0;
           DVLD_scntr_ecc  <= 'h0;
        end
        else begin
           DVLD_async_ecc  <= DVLD_async;
           DVLD_sync_ecc   <= DVLD_sync;
           DVLD_scntr_ecc  <= DVLD_scntr;
        end
     end
   // --------------------------------------------------------------------------
   // Generate top-level read data valid output
   // --------------------------------------------------------------------------         
   generate
      if (SYNC == 0 && FWFT == 0 && PREFETCH == 0) begin
         assign DVLD = (ECC == 1) ? DVLD_async_ecc : DVLD_async;  
      end
   endgenerate
   generate
      if (((SYNC == 1) && (RDEPTH == WDEPTH) && (ESTOP == 1) && (FSTOP ==  1)) && FWFT == 0 && PREFETCH == 0) begin  
         assign DVLD = (ECC == 1) ? DVLD_scntr_ecc : DVLD_scntr;  
      end
   endgenerate
   generate
      if ((SYNC == 1) && (RDEPTH == WDEPTH) && (ESTOP == 0 || FSTOP ==  0) && FWFT == 0 && PREFETCH == 0) begin  
         assign DVLD = (ECC == 1) ? DVLD_sync_ecc : DVLD_sync;  
      end
   endgenerate
   generate
      if (SYNC == 1 &&  (RDEPTH != WDEPTH) && FWFT == 0 && PREFETCH == 0) begin
         assign DVLD = (ECC == 1) ? DVLD_sync_ecc : DVLD_sync;  
      end
   endgenerate
   generate
      if (FWFT == 1 || PREFETCH == 1) begin
         assign DVLD = (READ_DVALID == 1) ? fwft_dvld : 1'b0;
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Generate read enable to the FIFO controller based on whether FWFT/PREFETCH
   // mode is selected or not.
   // --------------------------------------------------------------------------         
   assign  fifo_re_in   = ((FWFT == 1 || PREFETCH == 1) && PIPE != 0) ? fifo_rd_en : RE;   
   //assign  fifo_re_in   = ((FWFT == 1 || PREFETCH == 1) && PIPE == 1) ? RE : RE;   // added by mahesh

   // --------------------------------------------------------------------------
   // Generate top-level outputs to External memory
   // --------------------------------------------------------------------------
   assign MEMWADDR     = (CTRL_TYPE == 1) ? fifo_MEMWADDR : 'h0;
   assign MEMWE        = (CTRL_TYPE == 1) ? fifo_MEMWE    : 1'b0;
   assign MEMWD        = (CTRL_TYPE == 1) ? DATA          : 'h0;
   assign #1 MEMRE     = (CTRL_TYPE == 1) ? fifo_MEMRE    : 1'b0; 
   assign #1 MEMRADDR  = (CTRL_TYPE == 1) ? ((FWFT == 1 && PIPE != 0) ? fwft_MEMRADDR : ((PREFETCH == 1 && PIPE != 0) ? fwft_MEMRADDR : fifo_MEMRADDR)) : 'h0;

   // --------------------------------------------------------------------------
   // Based on the 'SYNC' parameter generate either Synchronous FIFO or
   // Asynchronous FIFO
   // --------------------------------------------------------------------------
   generate
        if ((SYNC == 1) && (RDEPTH == WDEPTH) && (ESTOP == 1) && (FSTOP ==  1))
        // ------------------------------------
        // Synchronous FIFO operation Instance
    	// Equal Depths and No wrap around
        // ------------------------------------
		
            BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_sync_scntr #(
                .WRITE_WIDTH      (WWIDTH         ),
                .WRITE_DEPTH      ((ceil_log2(WDEPTH))),
                .FULL_WRITE_DEPTH (WDEPTH         ),
                .READ_WIDTH       (RWIDTH         ),
                .READ_DEPTH       ((ceil_log2(RDEPTH))),
                .FULL_READ_DEPTH  (RDEPTH         ),
                .WCLK_HIGH        (WCLK_EDGE      ),
                .PREFETCH         (PREFETCH       ),
                .FWFT             (FWFT           ), 
                .RESET_LOW        (RESET_POLARITY ),
                .WRITE_LOW        (WE_POLARITY    ),
                .READ_LOW         (RE_POLARITY    ),
                .AF_FLAG_STATIC   (AF_STATIC_EN   ),
                .AE_FLAG_STATIC   (AE_STATIC_EN   ),
                .AE_DYN_EN        (AE_DYN_EN      ),
				.AF_DYN_EN        (AF_DYN_EN      ),
				.AFULL_VAL        (AFVAL          ),
                .AEMPTY_VAL       (AEVAL          ),
                .ESTOP            (ESTOP          ),
                .FSTOP            (FSTOP          ),
                .PIPE             (PIPE           ),
                .SYNC_RESET       (SYNC_RESET     ),//uncommented in v3.0
                .REGISTER_RADDR   (PIPE           ),
                .READ_DVALID      (READ_DVALID    ),
                .WRITE_ACK        (WRITE_ACK      ),
				.OVERFLOW_EN      (OVERFLOW_EN    ),
                .UNDERFLOW_EN     (UNDERFLOW_EN   ),
                .WRCNT_EN         (WRCNT_EN       ),
                .RDCNT_EN         (RDCNT_EN       ),
				.ECC              (ECC            ),
				.FAMILY			  (FAMILY		  )
            )
                fifo_corefifo_sync_scntr (
                    .clk                   (CLK                 ),
                    //.reset               (RESET               ),
                    .aresetn               (aresetn             ),
                    .sresetn               (sresetn             ),
                    .we                    (WE                  ),
                    .re                    (fifo_re_in          ),  
                    .re_top                (RE                  ),
                    .full                  (FULL                ),
                    .afull                 (AFULL               ),
                    .afull_in_dyn_thold    (AF_THRSHLD          ),
                    .wrcnt                 (WRCNT               ),
                    .empty                 (EMPTY1              ),
                    .aempty                (AEMPTY1             ),
                    .aempty_in_dyn_thold   (AE_THRSHLD          ),
                    .rdcnt                 (RDCNT               ),
                    .underflow             (UNDERFLOW           ),
                    .overflow              (OVERFLOW            ),
                    .dvld                  (DVLD_scntr          ),
                    .wack                  (WACK                ),
                    .memwaddr              (fifo_MEMWADDR       ),
                    .memwe                 (fifo_MEMWE          ),
                    .memraddr              (fifo_MEMRADDR       ),
                    .memre                 (fifo_MEMRE          ),
                    .empty_top_fwft        (EMPTY2              )  
                );
   
      else if (SYNC == 1 &&  (WDEPTH >= RDEPTH)) begin
        // ------------------------------------
        // Synchronous FIFO operation Instance
        // ------------------------------------
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_sync  #(
                          .WRITE_WIDTH      (WWIDTH        ),
                          .WRITE_DEPTH      ((ceil_log2(WDEPTH))),
                          .FULL_WRITE_DEPTH (WDEPTH        ),
                          .READ_WIDTH       (RWIDTH        ),
                          .READ_DEPTH       ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_WRDEPTH ((ceil_log2(WDEPTH))),
                          .VAR_ASPECT_RDDEPTH ((ceil_log2(WDEPTH))),
                          .FULL_READ_DEPTH  (RDEPTH        ),
                          .PREFETCH         (PREFETCH      ),
                          .FWFT             (FWFT          ),
                          .WCLK_HIGH        (WCLK_EDGE     ),
                          .RESET_LOW        (RESET_POLARITY),
                          .WRITE_LOW        (WE_POLARITY   ),
                          .READ_LOW         (RE_POLARITY   ),
                          .AF_FLAG_STATIC   (AF_STATIC_EN  ),
                          .AE_FLAG_STATIC   (AE_STATIC_EN  ),
                          .AE_DYN_EN        (AE_DYN_EN     ),
                          .AF_DYN_EN        (AF_DYN_EN     ),
                          .AFULL_VAL        (AFVAL         ),
                          .AEMPTY_VAL       (AEVAL         ),
                          .ESTOP            (ESTOP         ),
                          .FSTOP            (FSTOP         ),
                          .PIPE             (PIPE          ),
                          .SYNC_RESET       (SYNC_RESET    ),//uncommented in v3.0
                          .REGISTER_RADDR   (PIPE          ),
                          .READ_DVALID      (READ_DVALID   ),
                          .WRITE_ACK        (WRITE_ACK     ),
    	              	  .OVERFLOW_EN      (OVERFLOW_EN   ),
                          .UNDERFLOW_EN     (UNDERFLOW_EN  ),
                          .WRCNT_EN         (WRCNT_EN      ),
                          .RDCNT_EN         (RDCNT_EN      )
                         ) 
                        U_corefifo_sync(
                                         .clk                   (CLK                 ),
                                         //.reset               (RESET               ),
										 .aresetn               (aresetn    	     ),
										 .sresetn               (sresetn    	     ),										 
                                         .we                    (WE                  ),
                                         .re                    (fifo_re_in          ),
                                         .empty_top_fwft        (EMPTY2              ),
                                         .re_top                (RE                  ),
                                         .full                  (FULL                ),
                                         .afull                 (AFULL               ),
                                         .afull_in_dyn_thold    (AF_THRSHLD          ),
										 .wrcnt                 (WRCNT               ),
                                         .empty                 (EMPTY1              ),
                                         .aempty                (AEMPTY1             ),
                                         .aempty_in_dyn_thold   (AE_THRSHLD          ),
										 .rdcnt                 (RDCNT               ),
                                         .underflow             (UNDERFLOW           ),
                                         .overflow              (OVERFLOW            ),
                                         .dvld                  (DVLD_sync           ),
                                         .wack                  (WACK                ),
                                         .memwaddr              (fifo_MEMWADDR       ),
                                         .memwe                 (fifo_MEMWE          ),
                                         .memraddr              (fifo_MEMRADDR       ),
                                         .memre                 (fifo_MEMRE          )
                                         );
      end
      else if (SYNC == 1 &&  (RDEPTH > WDEPTH)) begin
        // ------------------------------------
        // Synchronous FIFO operation Instance
        // ------------------------------------
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_sync  #(
                          .WRITE_WIDTH      (WWIDTH        ),
                          .WRITE_DEPTH      ((ceil_log2(WDEPTH))),
                          .FULL_WRITE_DEPTH (WDEPTH        ),
                          .READ_WIDTH       (RWIDTH        ),
                          .READ_DEPTH       ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_WRDEPTH ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_RDDEPTH ((ceil_log2(RDEPTH))),
                          .FULL_READ_DEPTH  (RDEPTH        ),
                          .PREFETCH         (PREFETCH      ),
                          .FWFT             (FWFT          ),
                          .WCLK_HIGH        (WCLK_EDGE     ),
                          .RESET_LOW        (RESET_POLARITY),
                          .WRITE_LOW        (WE_POLARITY   ),
                          .READ_LOW         (RE_POLARITY   ),
                          .AF_FLAG_STATIC   (AF_STATIC_EN   ),
                          .AE_FLAG_STATIC   (AE_STATIC_EN   ),
                          .AE_DYN_EN        (AE_DYN_EN      ),
						  .AF_DYN_EN        (AF_DYN_EN      ),
						  .AFULL_VAL        (AFVAL         ),
                          .AEMPTY_VAL       (AEVAL         ),
                          .ESTOP            (ESTOP         ),
                          .FSTOP            (FSTOP         ),
                          .PIPE             (PIPE          ),
                          .SYNC_RESET       (SYNC_RESET    ),//uncommented in v3.0
                          .REGISTER_RADDR   (PIPE          ),
                          .READ_DVALID      (READ_DVALID   ),
                          .WRITE_ACK        (WRITE_ACK     ),
    	              	  .OVERFLOW_EN      (OVERFLOW_EN   ),
                          .UNDERFLOW_EN     (UNDERFLOW_EN  ),
                          .WRCNT_EN         (WRCNT_EN      ),
                          .RDCNT_EN         (RDCNT_EN      )
                         ) 
                        U_corefifo_sync(
                                         .clk                   (CLK                 ),
                                         //.reset            (RESET       ),
										 .aresetn               (aresetn    	     ),
										 .sresetn               (sresetn    	     ),										 
                                         .we                    (WE                  ),
                                         .re                    (fifo_re_in          ),
                                         .empty_top_fwft        (EMPTY2              ),
                                         .re_top                (RE                  ),
                                         .full                  (FULL                ),
                                         .afull                 (AFULL               ),
                                         .afull_in_dyn_thold    (AF_THRSHLD  ),
										 .wrcnt                 (WRCNT               ),
                                         .empty                 (EMPTY1              ),
                                         .aempty_in_dyn_thold   (AE_THRSHLD ),
										 .aempty                (AEMPTY1             ),
                                         .rdcnt                 (RDCNT               ),
                                         .underflow             (UNDERFLOW           ),
                                         .overflow              (OVERFLOW            ),
                                         .dvld                  (DVLD_sync           ),
                                         .wack                  (WACK                ),
                                         .memwaddr              (fifo_MEMWADDR       ),
                                         .memwe                 (fifo_MEMWE          ),
                                         .memraddr              (fifo_MEMRADDR       ),
                                         .memre                 (fifo_MEMRE          )
                                         );

      end
      else if (SYNC == 0 && (WDEPTH >= RDEPTH) ) begin  // for variable aspect ratio
        // --------------------------------------------------------------------
        // Asynchronous FIFO operation Instance with Controller Only operation
        // --------------------------------------------------------------------
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_async  #(
                          .WRITE_WIDTH      (WWIDTH         ),
                          .WRITE_DEPTH      ((ceil_log2(WDEPTH))),
                          .FULL_WRITE_DEPTH (WDEPTH         ),
                          .READ_WIDTH       (RWIDTH         ),
                          .READ_DEPTH       ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_WRDEPTH ((ceil_log2(WDEPTH))),
                          .VAR_ASPECT_RDDEPTH ((ceil_log2(WDEPTH))),
                          .FULL_READ_DEPTH  (RDEPTH         ),
                          .PREFETCH         (PREFETCH       ),
                          .FWFT             (FWFT           ),
                          .WCLK_HIGH        (WCLK_EDGE      ),
                          .RCLK_HIGH        (RCLK_EDGE      ),
                          .RESET_LOW        (RESET_POLARITY ),
                          .WRITE_LOW        (WE_POLARITY    ),
                          .READ_LOW         (RE_POLARITY    ),
                          .AF_FLAG_STATIC   (AF_STATIC_EN   ),
                          .AE_FLAG_STATIC   (AE_STATIC_EN   ),
                          .AE_DYN_EN        (AE_DYN_EN      ),
						  .AF_DYN_EN        (AF_DYN_EN      ),
						  .AFULL_VAL        (AFVAL          ),
                          .AEMPTY_VAL       (AEVAL          ),
                          .ESTOP            (ESTOP          ),
                          .FSTOP            (FSTOP          ),
                          .PIPE             (PIPE           ),
                          .SYNC_RESET       (SYNC_RESET     ),//uncommented in v3.0
                          .REGISTER_RADDR   (PIPE           ),
                          .READ_DVALID      (READ_DVALID    ),
                          .WRITE_ACK        (WRITE_ACK      ),
	       	              .OVERFLOW_EN      (OVERFLOW_EN    ),
                          .UNDERFLOW_EN     (UNDERFLOW_EN   ),
                          .WRCNT_EN         (WRCNT_EN       ),
						  .NUM_STAGES       (NUM_STAGES     ),
                          .RDCNT_EN         (RDCNT_EN       )

                         ) 
                        U_corefifo_async(
                                         .rclk                   (RCLOCK          ),
                                         .wclk                   (WCLOCK          ),
                                         //.reset_rclk       (reset_rclk      ),//commented in v3.0
                                         //.reset_wclk       (reset_wclk      ),//commented in v3.0
                                         //.RRESET       (RRESET      ),//Added in v3.0
                                         //.WRESET       (WRESET      ),	//Added in v3.0	
										 .aresetn_wclk          (aresetn_wclk        ),
										 .aresetn_rclk          (aresetn_rclk        ),
										 .sresetn_wclk          (sresetn_wclk        ),
										 .sresetn_rclk          (sresetn_rclk        ),											 
                                         .we                    (WE                  ),
                                         .re                    (fifo_re_in          ),  
                                         .re_top                (RE                  ),
                                         .full                  (FULL                ),
                                         .afull                 (AFULL               ),
                                         .afull_in_dyn_thold    (AF_THRSHLD  ),
										 .wrcnt                 (WRCNT               ),
                                         .empty                 (EMPTY1              ),
                                         .aempty                (AEMPTY1             ),
                                         .aempty_in_dyn_thold   (AE_THRSHLD ),
										 .rdcnt                 (RDCNT               ),
                                         .underflow             (UNDERFLOW           ),
                                         .overflow              (OVERFLOW            ),
                                         .dvld                  (DVLD_async          ),
                                         .wack                  (WACK                ),
                                         .memwaddr              (fifo_MEMWADDR       ),
                                         .memwe                 (fifo_MEMWE          ),
                                         .memraddr              (fifo_MEMRADDR       ),
                                         .memre                 (fifo_MEMRE          )
                                         );
      end
      else if (SYNC == 0 && (RDEPTH > WDEPTH) ) begin  // for variable aspect ratio
        // --------------------------------------------------------------------
        // Asynchronous FIFO operation Instance with Controller Only operation
        // --------------------------------------------------------------------
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_async  #(
                          .WRITE_WIDTH      (WWIDTH         ),
                          .WRITE_DEPTH      ((ceil_log2(WDEPTH))),
                          .FULL_WRITE_DEPTH (WDEPTH         ),
                          .READ_WIDTH       (RWIDTH         ),
                          .READ_DEPTH       ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_WRDEPTH ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_RDDEPTH ((ceil_log2(RDEPTH))),
                          .FULL_READ_DEPTH  (RDEPTH         ),
                          .PREFETCH         (PREFETCH       ),
                          .FWFT             (FWFT           ),
                          .WCLK_HIGH        (WCLK_EDGE      ),
                          .RCLK_HIGH        (RCLK_EDGE      ),
                          .RESET_LOW        (RESET_POLARITY ),
                          .WRITE_LOW        (WE_POLARITY    ),
                          .READ_LOW         (RE_POLARITY    ),
                          .AF_FLAG_STATIC   (AF_STATIC_EN   ),
                          .AE_FLAG_STATIC   (AE_STATIC_EN   ),
                          .AE_DYN_EN        (AE_DYN_EN      ),
						  .AF_DYN_EN        (AF_DYN_EN      ),
						  .AFULL_VAL        (AFVAL          ),
                          .AEMPTY_VAL       (AEVAL          ),
                          .ESTOP            (ESTOP          ),
                          .FSTOP            (FSTOP          ),
                          .PIPE             (PIPE           ),
                          .SYNC_RESET       (SYNC_RESET     ),//uncommented in v3.0
                          .REGISTER_RADDR   (PIPE           ),
                          .READ_DVALID      (READ_DVALID    ),
                          .WRITE_ACK        (WRITE_ACK      ),
	       	              .OVERFLOW_EN      (OVERFLOW_EN    ),
                          .UNDERFLOW_EN     (UNDERFLOW_EN   ),
						  .NUM_STAGES       (NUM_STAGES     ),
                          .WRCNT_EN         (WRCNT_EN       ),
                          .RDCNT_EN         (RDCNT_EN       )

                         ) 
                        U_corefifo_async(
                                         .rclk                  (RCLOCK              ),
                                         .wclk                  (WCLOCK              ),
                                         //.reset_rclk       (reset_rclk      ),commented in v3.0
                                         //.reset_wclk       (reset_wclk      ),commented in v3.0
                                         //.WRESET       (WRESET      ),//Added in v3.0
                                         //.RRESET       (RRESET      ),//Added in v3.0
										 .aresetn_wclk          (aresetn_wclk        ),
										 .aresetn_rclk          (aresetn_rclk        ),
										 .sresetn_wclk          (sresetn_wclk        ),
										 .sresetn_rclk          (sresetn_rclk        ),											 
                                         .we                    (WE                  ),
                                         .re                    (RE                  ),
                                         .re_top                (RE                  ),
                                         .full                  (FULL                ),
                                         .afull                 (AFULL               ),
                                         .afull_in_dyn_thold    (AF_THRSHLD  ),
										 .wrcnt                 (WRCNT               ),
                                         .empty                 (EMPTY1              ),
                                         .aempty                (AEMPTY1             ),
                                         .aempty_in_dyn_thold   (AE_THRSHLD ),
										 .rdcnt                 (RDCNT               ),
                                         .underflow             (UNDERFLOW           ),
                                         .overflow              (OVERFLOW            ),
                                         .dvld                  (DVLD_async          ),
                                         .wack                  (WACK                ),
                                         .memwaddr              (fifo_MEMWADDR       ),
                                         .memwe                 (fifo_MEMWE          ),
                                         .memraddr              (fifo_MEMRADDR       ),
                                         .memre                 (fifo_MEMRE          )
                                         );
      end
      else begin  // for variable aspect ratio
        // --------------------------------------------------------------------
        // Asynchronous FIFO operation Instance with Controller Only operation
        // --------------------------------------------------------------------
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_async  #(
                          .WRITE_WIDTH      (WWIDTH         ),
                          .WRITE_DEPTH      ((ceil_log2(WDEPTH))),
                          .FULL_WRITE_DEPTH (WDEPTH         ),
                          .READ_WIDTH       (RWIDTH         ),
                          .READ_DEPTH       ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_RDDEPTH ((ceil_log2(RDEPTH))),
                          .VAR_ASPECT_WRDEPTH ((ceil_log2(WDEPTH))),
                          .FULL_READ_DEPTH  (RDEPTH         ),
                          .PREFETCH         (PREFETCH       ),
                          .FWFT             (FWFT           ),
                          .WCLK_HIGH        (WCLK_EDGE      ),
                          .RCLK_HIGH        (RCLK_EDGE      ),
                          .RESET_LOW        (RESET_POLARITY ),
                          .WRITE_LOW        (WE_POLARITY    ),
                          .READ_LOW         (RE_POLARITY    ),
                          .AF_FLAG_STATIC   (AF_STATIC_EN   ),
                          .AE_FLAG_STATIC   (AE_STATIC_EN   ),
                          .AE_DYN_EN        (AE_DYN_EN      ),
						  .AF_DYN_EN        (AF_DYN_EN      ),
						  .AFULL_VAL        (AFVAL          ),
                          .AEMPTY_VAL       (AEVAL          ),
                          .ESTOP            (ESTOP          ),
                          .FSTOP            (FSTOP          ),
                          .PIPE             (PIPE           ),
                          .SYNC_RESET       (SYNC_RESET     ),//uncommented in v3.0
                          .REGISTER_RADDR   (PIPE           ),
                          .READ_DVALID      (READ_DVALID    ),
                          .WRITE_ACK        (WRITE_ACK      ),
    	       	          .OVERFLOW_EN      (OVERFLOW_EN    ),
                          .UNDERFLOW_EN     (UNDERFLOW_EN   ),
						  .NUM_STAGES       (NUM_STAGES     ),
                          .WRCNT_EN         (WRCNT_EN       ),
                          .RDCNT_EN         (RDCNT_EN       )

                         ) 
                        U_corefifo_async(
                                         .rclk             (RCLOCK          ),
                                         .wclk             (WCLOCK          ),
                                          //.reset_rclk       (reset_rclk      ),commented in v3.0
                                         //.reset_wclk       (reset_wclk      ),commented in v3.0
                                         //.WRESET       (WRESET      ),//Added in v3.0
                                         //.RRESET       (RRESET      ),//Added in v3.0
										 .aresetn_wclk          (aresetn_wclk        ),
										 .aresetn_rclk          (aresetn_rclk        ),
										 .sresetn_wclk          (sresetn_wclk        ),
										 .sresetn_rclk          (sresetn_rclk        ),										 
                                         .we                    (WE                  ),
                                         .re                    (RE                  ),
                                         .re_top                (RE                  ),
                                         .full                  (FULL                ),
                                         .afull                 (AFULL               ),
                                         .afull_in_dyn_thold    (AF_THRSHLD  ),
										 .wrcnt                 (WRCNT               ),
                                         .empty                 (EMPTY1              ),
                                         .aempty                (AEMPTY1             ),
                                         .aempty_in_dyn_thold   (AE_THRSHLD ),
										 .rdcnt                 (RDCNT               ),
                                         .underflow             (UNDERFLOW           ),
                                         .overflow              (OVERFLOW            ),
                                         .dvld                  (DVLD_async          ),
                                         .wack                  (WACK                ),
                                         .memwaddr              (fifo_MEMWADDR       ),
                                         .memwe                 (fifo_MEMWE          ),
                                         .memraddr              (fifo_MEMRADDR       ),
                                         .memre                 (fifo_MEMRE          )
                                         );
      end      
   endgenerate
   
   // -----------------------------------------------------------------------
   // FWFT/Prefetch logic
   // The module is used to provide FWFT and Prefetch logic.
   // -----------------------------------------------------------------------
   generate
      if ((FWFT == 1 || PREFETCH == 1) && PIPE != 0)  
   
        // FWFT module instance 
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_fwft #(
   	               .ECC             (ECC            ),
   	               .PIPE            (PIPE           ), 
                   .RWIDTH          (RWIDTH         ),
                   .WWIDTH          (WWIDTH         ),
                   .RCLK_HIGH       (RCLK_EDGE      ),
                   .WCLK_HIGH       (WCLK_EDGE      ),
                   .RESET_LOW       (RESET_POLARITY ),
                   .WRITE_LOW       (WE_POLARITY    ),
                   .READ_LOW        (RE_POLARITY    ),
                   .PREFETCH        (PREFETCH       ),
                   .FWFT            (FWFT           ),
                   .SYNC            (SYNC           ),
                   .SYNC_RESET      (SYNC_RESET     ),//uncommented in v3.0
                   .RDEPTH          (ceil_log2(RDEPTH))
                   )
          u_corefifo_fwft(
                     .rd_clk                   (RCLOCK               ),                         
                     .wr_clk                   (WCLOCK               ),                         
                     .clk                      (CLK                  ),                         
                     //.reset_rclk_top         (reset_rclk           ),commented in v3.0   
                     //.reset_wclk_top         (reset_wclk           ),commented in v3.0   
   				     .aresetn_wclk             (aresetn_wclk         ),                           
   				     .aresetn_rclk             (aresetn_rclk         ),                           
   				     .sresetn_wclk             (sresetn_wclk         ),                           
   				     .sresetn_rclk             (sresetn_rclk         ),                           
                     .empty                    (EMPTY2               ),                         
                     .aempty                   (AEMPTY2              ),                         
                     .rd_en                    (RE                   ),                         
                     .fifo_rd_en               (fifo_rd_en           ),                         
                     .fifo_dout                (mem_pf_RD            ),                         
                     .fifo_empty               (EMPTY1               ),
                     .fifo_aempty              (AEMPTY1              ),					 
                     .wr_en                    (WE                   ),                         
                     .din                      (DATA                 ),                         
                     .fwft_dvld                (fwft_dvld            ),                         
                     .reg_valid                (fwft_reg_valid       ),                         
                     .fifo_MEMRADDR            (fifo_MEMRADDR        ),                         
                     .fwft_MEMRADDR            (fwft_MEMRADDR        ),                         
                     .dout                     (fwft_Q               )                          
                     );                                                                  
                                                                                         
                                                                                         
   endgenerate 

   // --------------------------------------------------------------------------
   // Provides read address to ram memory
   // --------------------------------------------------------------------------
   generate
      if(FWFT == 0 && PREFETCH == 0) begin
        //assign #1 ram_raddr = fifo_MEMRADDR;   commented in v3.0
        assign ram_raddr = fifo_MEMRADDR;  //uncommented in v3.0
      end
   endgenerate

   generate
      if(FWFT == 1 && PIPE != 0) begin
         //assign #1 ram_raddr = fwft_MEMRADDR;  commented in v3.0 
         assign  ram_raddr = fwft_MEMRADDR;   
      end
   endgenerate

   generate
      if(PREFETCH == 1 && PIPE != 0) begin
         //assign #1 ram_raddr = fwft_MEMRADDR;  commented in v3.0 
         assign  ram_raddr = fwft_MEMRADDR;  
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Provides read address to ram memory
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
   begin
      if(!aresetn_rclk | !sresetn_rclk) 
	  begin
         re_set    <= 'h0;
         re_set_d1 <= 'h0;
         re_set_d2 <= 'h0;
      end
      else 
	  begin
         if(fifo_MEMRE && !REN_d1) 
		 begin      
            re_set <= 1'b0;
         end
         else if(!fifo_MEMRE && REN_d1) 
		 begin  
            re_set <= 1'b1;
         end
         if(REN_d1 && !REN_d2) 
		 begin      
            re_set_d1 <= 1'b0;
         end
         else if(!REN_d1 && REN_d2) 
		 begin  
            re_set_d1 <= 1'b1;
         end
	     if(REN_d2 && !REN_d3) 
	     begin      
            re_set_d2 <= 1'b0;
         end
         else if(!REN_d2 && REN_d3) 
	     begin  
            re_set_d2 <= 1'b1;
         end
	  end
   end	 

     always @(posedge pos_rclk or negedge aresetn_rclk)
       begin
          if(!aresetn_rclk | !sresetn_rclk ) begin
            RDATA_r <= 'h0;
          end
          else if(!fifo_MEMRE && REN_d1) begin
             RDATA_r <= RDATA_int;
          end
       end
     
   // --------------------------------------------------------------------------
   // Maintain the last read data
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)   
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           fwft_Q_r <= 'h0;
        end
        else begin
           fwft_Q_r <= Q;
        end
     end

   always @(posedge pos_rclk or negedge aresetn_rclk)   
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           RDATA_r_pre <= 'h0;
        end
        else if(fifo_MEMRE) begin
           RDATA_r_pre <= Q ;
        end
     end

   always @(posedge pos_rclk or negedge aresetn_rclk)   
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           RDATA_r1 <= 'h0;
        end
        else if(!REN_d1 && REN_d2) begin
           RDATA_r1 <= RDATA_int;
        end
     end

   always @(posedge pos_rclk or negedge aresetn_rclk)   
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           RDATA_r2 <= 'h0;
        end
        else if(!REN_d2 && REN_d3) begin
           RDATA_r2 <= RDATA_int;
        end
     end

   assign RE_pol  = RE_POLARITY  ? (~RE) : (RE); 

   always @(posedge pos_rclk or negedge aresetn_rclk)
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           REN_d1      <= 'h0;
           REN_d2      <= 'h0;
           REN_d3      <= 'h0;         
           RE_d1       <= 'h0;
           RE_d2       <= 'h0;
           RE_d3       <= 'h0;         
           re_pulse_d1 <= 'h0;
           re_pulse_d2 <= 'h0;
           re_pulse_d3 <= 'h0;         
        end
        else begin
           RE_d1       <= RE_pol;
           RE_d2       <= RE_d1;
           RE_d3       <= RE_d2;       
           REN_d1      <= fifo_MEMRE;
           REN_d2      <= REN_d1;
           REN_d3      <= REN_d2;      
           re_pulse_d1 <= re_pulse;
           re_pulse_d2 <= re_pulse_d1;
           re_pulse_d3 <= re_pulse_d2; 
        end
     end

   assign re_pulse     = (!fifo_MEMRE & REN_d1) | re_set;
   assign re_pulse_pre = !fifo_MEMRE;
   
   
   assign int_MEMRD_fwft_pipe1  =  (re_set     & (RE_d1==0      )) ? RDATA_r     : RDATA_int;  
   assign int_MEMRD_fwft_pipe2  =  (re_set_d1  & (RE_d2==0      )) ? RDATA_r1    : RDATA_int; 
   assign int_MEMRD_fwft_pipe3  =  (re_set_d2    & (RE_d3==0))  ? RDATA_r2    : RDATA_int; 
   assign int_MEMRD_pipe0       =  (re_pulse     & (RE_pol==0)) ? RDATA_r_pre : RDATA_int;
   assign int_MEMRD_pipe1       =  (re_pulse_d1  & (RE_d1==0 ) & (ECC == 0 || ECC == 2)) ? RDATA_r     : RDATA_int;  
   assign int_MEMRD_pipe2       =  (re_pulse_d2  & (RE_d2==0 ) & (ECC == 0 || ECC == 2)) ? RDATA_r1    : RDATA_int; 
   
   
   assign int_MEMRD_pipe1_ecc1 =  (re_pulse_d2  & (RE_d2==0 ) & (ECC == 1)) ? RDATA_r1    : RDATA_int;  
   assign int_MEMRD_pipe2_ecc1 =  (re_pulse_d3  & (RE_d3==0 ) & (ECC == 1)) ? RDATA_r2    : RDATA_int;  

   // FWFT/Prefetch PIPE=1 uses _fwft_pipe1. The FWFT block has
   // a 2-flop pipeline with a local data capture register (fifo_dout_r) that
   // breaks the combinational path. The _pipe1 hold-mux presents RDATA_r
   // when reads pause and RDATA_int when reads are active, matching the
   // 1-cycle PIPE=1 RAM latency needed for fifo_dout_r capture at fifo_rd_en_d1.
     // FWFT+PIPE=2+ECC=0 hold-mux timing correction.
     // The PIPE=2 inferred RAM has a 2-cycle read latency. The last in-flight read's
     // data arrives at RDATA_int exactly when re_set_d1 fires and RDATA_r1 is captured.
     // Using re_set_d1/RDATA_r1 causes the hold-mux to latch data from the second-to-last
     // read (one cycle too early), producing a data duplication every FIFO fill cycle.
     // Fix: route FWFT+PIPE=2+ECC=0 to int_MEMRD_fwft_pipe3 (uses re_set_d2/RDATA_r2),
     // which fires one cycle later — after the last read's data is fully stable.
   assign int_MEMRD       =  ((FWFT == 1 | PREFETCH == 1) & PIPE == 1 & ECC != 1) ? int_MEMRD_fwft_pipe1 : 
                             ((FWFT == 1 | PREFETCH == 1) & (PIPE == 2 & ECC == 1))   ?  int_MEMRD_fwft_pipe3 :
                             ((FWFT == 1 | PREFETCH == 1) & ((PIPE == ECC) | (PIPE == 2 & ECC == 0))) ? int_MEMRD_fwft_pipe2 :
                             (PIPE == 0)                            ? int_MEMRD_pipe0                      : 
                             (PIPE == 1 && ECC != 1)                ? int_MEMRD_pipe1                      :  
                             (PIPE == 2 && ECC != 1)                ? int_MEMRD_pipe2                      : 
                             (PIPE == 1 && ECC == 1)                ? int_MEMRD_pipe1_ecc1                 : 
                             (PIPE == 2 && ECC == 1)                ? int_MEMRD_pipe2_ecc1                 : 
                             RDATA_int; 

   assign ext_MEMRD_fwft       =  (re_set     & (RE_d1==0      )) ? RDATA_ext_r  : MEMRD;

   assign ext_MEMRD_pipe0 =  (re_pulse     & (RE_pol==0)) ? RDATA_r_pre  : MEMRD;
   assign ext_MEMRD_pipe1 =  (re_pulse_d1  & (RE_d1==0 )) ? RDATA_ext_r  : MEMRD;
   assign ext_MEMRD_pipe2 =  (re_pulse_d2  & (RE_d2==0 )) ? RDATA_ext_r1 : MEMRD;
    // FWFT/Prefetch PIPE=1 uses ext_MEMRD_fwft (1-cycle hold-mux),
    // matching int_MEMRD_fwft_pipe1 for the internal memory path. The FWFT
    // block's fifo_dout_r register provides the extra pipeline stage.
    assign ext_MEMRD       =  ((FWFT == 1) & (PIPE == 1))     ? ext_MEMRD_fwft :
                              ((PREFETCH == 1) & (PIPE == 1)) ? ext_MEMRD_fwft :
                             (FWFT == 1)     ? ext_MEMRD_fwft      : 
                             (PREFETCH == 1) ? ext_MEMRD_fwft  :
                             (PIPE == 0)? ext_MEMRD_pipe0      : 
                             (PIPE == 1) ? ext_MEMRD_pipe1     : 
                             (PIPE == 2) ? ext_MEMRD_pipe2     : 
							 MEMRD; 
    


    
   // --------------------------------------------------------------------------
   // Get the READ Data from internal or external memory based on CTRL_TYPE
   // --------------------------------------------------------------------------
   assign mem_pf_RD = (CTRL_TYPE == 1) ? ext_MEMRD : int_MEMRD;

   //assign #1 fifo_MEMRE_int = fifo_MEMRE;  commented in v3.0 
	assign fifo_MEMRE_int = fifo_MEMRE; // uncommented in v3.0 


   always @(posedge pos_rclk or negedge aresetn_rclk)
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           RDATA_ext_r <= 'h0;
        end
        else if(!fifo_MEMRE && REN_d1) begin
           RDATA_ext_r <= MEMRD;
        end
     end
   
   always @(posedge pos_rclk or negedge aresetn_rclk)  
     begin
        if(!aresetn_rclk | !sresetn_rclk) begin
           RDATA_ext_r1 <= 'h0;
        end
        else if(!REN_d1 && REN_d2) begin
           RDATA_ext_r1 <= MEMRD;
        end
     end


   // capture the RAM wrapper .SB_CORRECT/.DB_DETECT port output and are OR'd into the
   // top-level flags. This avoids multi-drive on SB_CORRECT/DB_DETECT while preserving
   // ECC information regardless of which port the RAM macro drives.
   // For FAMILY 28 , the wrapper routes .SB_CORRECT directly to A_SB_CORRECT.
   // For CTRL_TYPE 1 (controller only), no RAM wrapper exists.
   generate
     if (ECC != 0) begin
       if (FAMILY == 19 || FAMILY == 24 || FAMILY == 25 || FAMILY == 26 || FAMILY == 27) begin
	assign SB_CORRECT = (CTRL_TYPE == 2) ? (A_SB_CORRECT | W_SB_CORRECT) : ((CTRL_TYPE == 3) ? (A_SB_CORRECT | B_SB_CORRECT | W_SB_CORRECT) : 1'b0);
        assign DB_DETECT  = (CTRL_TYPE == 2) ? (A_DB_DETECT  | W_DB_DETECT ) : ((CTRL_TYPE == 3) ? (A_DB_DETECT  | B_DB_DETECT  | W_DB_DETECT ) : 1'b0);
       end
       else begin
	assign SB_CORRECT = (CTRL_TYPE == 2) ? A_SB_CORRECT : ((CTRL_TYPE == 3) ? (A_SB_CORRECT | B_SB_CORRECT) : 1'b0);
        assign DB_DETECT  = (CTRL_TYPE == 2) ? A_DB_DETECT  : ((CTRL_TYPE == 3) ? (A_DB_DETECT  | B_DB_DETECT ) : 1'b0);
       end
     end
	 
	 else 
		begin
			assign SB_CORRECT = 1'b0;
			assign DB_DETECT  = 1'b0;
		end
endgenerate



   // -----------------------------------------------------------------------
   // Memory wrapper instance
   // -----------------------------------------------------------------------
   
generate
   // CTRL_TYPE 
   //    1 - Controller Only
   //    2 - RAM1Kx18 
   //    3 - RAM64x18
   if (CTRL_TYPE != 1)
   begin
      // ECC         
      //   0 - ECC Disable
      //   1 - Pipelined ECC
      //   2 - Non-pipelined ECC
	  if (FAMILY == 28)
	  begin
            if (ECC == 0)
            begin	 
            BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis 
            #(            
            .RDEPTH_CAL   (RDEPTH_CAL ),
            .WDEPTH_CAL   (WDEPTH_CAL ),
            .RWIDTH       (RWIDTH     ),
            .WWIDTH       (WWIDTH     ),
            .SYNC         (SYNC       ),
            .ECC          (ECC        ),
            .FAMILY       (FAMILY     ),
            .RAM_OPT      (RAM_OPT    ),
            .PIPE         (PIPE       ),
            .RAM_SEL      (RAM_SEL    ),
            .RDEPTH       (RDEPTH     ),
            .WDEPTH       (WDEPTH     ) 
            )
            corefifo_raminfer_eccdis_inst
            (
             .CLK            (CLK           ),
             .WCLOCK         (WCLOCK        ),
             .RCLOCK         (RCLOCK        ),
             .DATA           (DATA          ),
             .fifo_MEMWADDR  (fifo_MEMWADDR ),
             .fifo_MEMWE     (fifo_MEMWE    ),
             .fifo_MEMRE_int (fifo_MEMRE_int),
             .RDATA_int      (RDATA_int_ram_gen_6 ),
             .ram_raddr      (ram_raddr     ),
              .aresetn        (aresetn_rclk  ),
              .sresetn        (sresetn_rclk  )
            );
	        end
            else
            begin
                BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_ram_wrapper
                #(
                  .RWIDTH       (RWIDTH    ),
                  .WWIDTH       (WWIDTH    ),
                  .WDEPTH_CAL   (WDEPTH_CAL),
                  .RDEPTH_CAL   (RDEPTH_CAL)  
                )
		  	  corefifo_ecc_ram_wrapper_inst 
                ( 
                 .DATA_IN      (DATA           ),    
                 .DATA_OUT     (RDATA_int_ram_gen_6   ),   
                 .WR_ADDR      (fifo_MEMWADDR  ),     
                 .RD_ADDR      (ram_raddr      ),     
                 .RD_EN        (fifo_MEMRE_int ),             
                 .WR_EN        (fifo_MEMWE     ),             
                 .CLK          (CLK            ),            
                 .WR_CLK       (WCLOCK         ),            
                 .RD_CLK       (RCLOCK         ),
		  	     .RD_PL_ARST_N (aresetn_rclk   ),  //use aresetn_rclk instead of RRESET_N	    
		  	     .RD_PL_SRST_N (sresetn_rclk   ),  //use sresetn_rclk instead of RRESET_N	    
                 .RD_PL_EN     (1'b1           ),          
                 .SB_CORRECT   (A_SB_CORRECT   ),        
                 .DB_DETECT    (A_DB_DETECT    )        
                );
            end
        end
	    else if (FAMILY == 19 || FAMILY == 24 || FAMILY == 25 || FAMILY == 26 || FAMILY == 27)
        begin
		     //-----------------------------------------------------------------------------------------
             // Libero (RAM Wrapper verilog file)   		
             //                                          		
             //                        LSRAM    uSRAM               LSRAM            uSRAM                LSRAM             uSRAM   		
             // .gen   WE Polarity      1       W_EN_POLARITY:1     WE_POLARITY:1    C_WEN_POLARITY:1     WE_POLARITY:1     C_WEN_POLARITY:1 		
             //        RE Polarity      1       BLK_POLARITY:1      RE_POLARITY:1    C_BLK_POLARITY:1     RE_POLARITY:1     C_BLK_POLARITY:1		
             //        WE              WEN      WEN                 WEN              WEN                  WEN               WEN		
             //        RE              REN      REN                 REN              REN                  REN               REN		
             // 		
             //                                                                                                                                  		
             // Audrey (MACRO RAM verilog file)                                          		
             //                                                                 		
             //                 LSRAM           uSRAM                                    		
             // WE Polarity       1             W_EN_POLARITY:1                          		
             // RE Polarity       1             BLK_POLARITY:1 		
             // WE              W_EN            W_EN 		
             // RE              R_EN            BLK_EN		
		     //-----------------------------------------------------------------------------------------
		    // Write and Read Enable Libero Wrapper LSRAM/uSRAM 
			wire    WEN_WRAP_EN, WEN_CTRL, REN_WRAP_EN, REN_CTRL; 
			
			assign  WEN_WRAP_EN  =  fifo_MEMWE;     // WEN for Libero Wrapper LSRAM/uSRAM 
			assign  REN_WRAP_EN  =  fifo_MEMRE_int; // REN for Libero Wrapper LSRAM/uSRAM 
			
			// Write and Read Enable Audrey macro LSRAM/uSRAM 
			assign  WEN_CTRL     =  ((LEGACY == 0) && (FAMILY == 26 || FAMILY == 27) && (CTRL_TYPE == 2) && (WE_POLARITY == 0))  ? ~fifo_MEMWE : fifo_MEMWE;                                                     // W_EN for Audrey
			assign  REN_CTRL     =  ((LEGACY == 0) && (FAMILY == 26 || FAMILY == 27) && (CTRL_TYPE == 2) && (RE_POLARITY == 0))  ? ~fifo_MEMRE_int : fifo_MEMRE_int;                                             // R_EN for LSRAM Audrey Wrapper 
					
			if(LEGACY) begin 
            BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_ram_wrapper #(
               .RWIDTH        (RWIDTH            ),
               .WWIDTH        (WWIDTH            ),
               .SYNC          (SYNC              ),
	           .SYNC_RESET    (SYNC_RESET        ),
	           //.RAM_OPT       (RAM_OPT           ),
               .PIPE          (PIPE              ),
               .CTRL_TYPE     (CTRL_TYPE         ),
               .RDEPTH        (ceil_log2t(RDEPTH)),
               .WDEPTH        (ceil_log2t(WDEPTH)),
               .WDEPTH_CAL    (WDEPTH_CAL        ),
               .RDEPTH_CAL    (RDEPTH_CAL        )
               )
            corefifo_ecc_ram_wrapper_inst (
               .W_DATA         (DATA            ),
               .WD             (DATA            ),
               .C_DIN          (DATA            ),
               .W_ADDR         (fifo_MEMWADDR   ),
               .WADDR          (fifo_MEMWADDR   ),
               .C_ADDR         (fifo_MEMWADDR   ),
               .W_EN           (WEN_CTRL         ),     
               //.C_WEN          (fifo_MEMWE      ),    
               .C_WEN          (WEN_WRAP_EN      ),     
               .WEN            (WEN_WRAP_EN      ),     
               .WBYTE_EN       (1'b0            ),    
               .R_EN           (REN_CTRL         ),    
               .REN            (REN_WRAP_EN    ),       
               .BLK_EN         (fifo_MEMRE_int  ),     
               .R_ADDR_EN      (fifo_MEMRE_int  ),
               .A_ADDR_EN      (fifo_MEMRE_int  ),
               .B_ADDR_EN      (fifo_MEMRE_int  ),               
		       .A_BLK          (fifo_MEMRE_int  ),
               .B_BLK          (fifo_MEMRE_int  ),
               .R_DATA         (R_DATA          ), 
               .RD             (RD              ), 
               .A_DOUT         (A_DOUT          ), 
               .R_ADDR         (ram_raddr       ),
               .A_ADDR         (ram_raddr       ),
               .B_ADDR         (ram_raddr       ),
               .RADDR          (ram_raddr       ),
               .CLK            (CLK             ),  
               .W_CLK          (WCLOCK          ),  
               .WCLK           (WCLOCK          ),  
               .C_CLK          (WCLOCK          ),  
               .R_CLK          (RCLOCK          ),  
               .RCLK           (RCLOCK          ),  
               .A_CLK          (RCLOCK          ),  
               .B_CLK          (RCLOCK          ),  
               .SB_CORRECT     (W_SB_CORRECT    ),  //route to intermediate to avoid multi-drive on SB_CORRECT
               .A_SB_CORRECT   (A_SB_CORRECT    ), 
               .B_SB_CORRECT   (B_SB_CORRECT    ), 
               .DB_DETECT      (W_DB_DETECT     ),  //route to intermediate to avoid multi-drive on DB_DETECT
               .A_DB_DETECT    (A_DB_DETECT     ),  
               .B_DB_DETECT    (B_DB_DETECT     ), 
               .R_DATA_ARST    (aresetn_rclk    ),	//use aresetn_rclk instead of RRESET_N		   
               .ARST_N         (aresetn_rclk    ),       			   
               .RD_SRST_N      (sresetn_rclk    ),       			   
               .RESET_N        (aresetn_rclk    ),       			   
               .A_DOUT_SRST_N  (sresetn_rclk    ),       			   
               .B_DOUT_SRST_N  (sresetn_rclk    ),       			   
               .R_DATA_ARST_N  (aresetn_rclk    ),       			   
               .R_DATA_SRST_N  (sresetn_rclk    ),       			   
               .R_ADDR_SRST_N  (sresetn_rclk    ),       			   
               .R_ADDR_ARST_N  (aresetn_rclk    ),       			   
               .A_ADDR_SRST_N  (sresetn_rclk    ),       			   
               .B_ADDR_SRST_N  (sresetn_rclk    ),
               // ECC-specific ports (BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_ram_wrapper wraps BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO_ram_wrapper
               // connected to the DATA_IN/OUT ECC wrapper chain)
               .DATA_IN        (DATA            ),      // ECC write data input
               //.DATA_OUT       (RDATA_int_pf    ),      // ECC read data output (used as RDATA_int)
               .INJECT_ERR_N   (8'hFF           ),      // No error injection in normal operation
               .WR_ADDR        (fifo_MEMWADDR   ),      // ECC write address
               .RD_ADDR        (ram_raddr       ),      // ECC read address
               .RD_EN          ('d1  ),      // ECC read enable
               .WR_EN          (fifo_MEMWE      ),      // ECC write enable
               .WR_CLK         (WCLOCK          ),      // ECC write clock
               .RD_CLK         (RCLOCK          ),      // ECC read clock
               .RD_PL_SRST_N   (sresetn_rclk    ),      // ECC read pipeline sync reset
               .RD_PL_ARST_N   (aresetn_rclk    ),      // ECC read pipeline async reset
               .RD_PL_EN       (1'b1            ),      // ECC read pipeline enable — always on
               .BUSY_FB        (1'b0            ),      // ECC busy feedback — not used
               .SLEEP_N        (1'b1            ),      // ECC sleep — deasserted (active)
               .ACCESS_BUSY    (                )       // ECC access busy — not used (output, leave open)
            );			
			end 
			else begin 
            BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_ram_wrapper #(
               .RWIDTH        (RWIDTH            ),
               .WWIDTH        (WWIDTH            ),
               .SYNC          (SYNC              ),
	           .SYNC_RESET    (SYNC_RESET        ),
	           //.RAM_OPT       (RAM_OPT           ),
               .PIPE          (PIPE              ),
               .CTRL_TYPE     (CTRL_TYPE         ),
               .RDEPTH        (ceil_log2t(RDEPTH)),
               .WDEPTH        (ceil_log2t(WDEPTH)),
               .WDEPTH_CAL    (WDEPTH_CAL        ),
               .RDEPTH_CAL    (RDEPTH_CAL        )
               )
            corefifo_ecc_ram_wrapper_inst (
               .W_DATA         (DATA            ),
               .WD             (DATA            ),
               .C_DIN          (DATA            ),
               .W_ADDR         (fifo_MEMWADDR   ),
               .WADDR          (fifo_MEMWADDR   ),
               .C_ADDR         (fifo_MEMWADDR   ),
               .W_EN           (WEN_CTRL         ),     
               //.C_WEN          (fifo_MEMWE      ),    
               .C_WEN          (WEN_WRAP_EN      ),     
               .WEN            (WEN_WRAP_EN      ),     
               .WBYTE_EN       (1'b0            ),    
               .R_EN           (REN_CTRL         ),     
               .REN            (REN_WRAP_EN    ),       
               .BLK_EN         (fifo_MEMRE_int  ),     
               .R_ADDR_EN      (fifo_MEMRE_int  ),
               .A_ADDR_EN      (fifo_MEMRE_int  ),
               .B_ADDR_EN      (fifo_MEMRE_int  ),               
		   .A_BLK          (fifo_MEMRE_int  ),
               .B_BLK          (fifo_MEMRE_int  ),
               .R_DATA         (R_DATA          ), 
               .RD             (RD              ), 
               .A_DOUT         (A_DOUT          ), 
               .R_ADDR         (ram_raddr       ),
               .A_ADDR         (ram_raddr       ),
               .B_ADDR         (ram_raddr       ),
               .RADDR          (ram_raddr       ),
               .CLK            (CLK             ),  
               .W_CLK          (WCLOCK          ),  
               .WCLK           (WCLOCK          ),  
               .C_CLK          (WCLOCK          ),  
               .R_CLK          (RCLOCK          ),  
               .RCLK           (RCLOCK          ),  
               .A_CLK          (RCLOCK          ),  
               .B_CLK          (RCLOCK          ),  
               .SB_CORRECT     (W_SB_CORRECT    ),  //route to intermediate to avoid multi-drive on SB_CORRECT
               .A_SB_CORRECT   (A_SB_CORRECT    ), 
               .B_SB_CORRECT   (B_SB_CORRECT    ), 
               .DB_DETECT      (W_DB_DETECT     ),  //route to intermediate to avoid multi-drive on DB_DETECT
               .A_DB_DETECT    (A_DB_DETECT     ),  
               .B_DB_DETECT    (B_DB_DETECT     ), 
               .R_DATA_ARST    (aresetn_rclk    ),	//use aresetn_rclk instead of RRESET_N		   
               .ARST_N         (aresetn_rclk    ),       			   
               .RD_SRST_N      (sresetn_rclk    ),       			   
               .RESET_N        (aresetn_rclk    ),       			   
               .A_DOUT_SRST_N  (sresetn_rclk    ),       			   
               .B_DOUT_SRST_N  (sresetn_rclk    ),       			   
               .R_DATA_ARST_N  (aresetn_rclk    ),       			   
               .R_DATA_SRST_N  (sresetn_rclk    ),       			   
               .R_ADDR_SRST_N  (sresetn_rclk    ),       			   
               .R_ADDR_ARST_N  (aresetn_rclk    ),       			   
               .A_ADDR_SRST_N  (sresetn_rclk    ),       			   
               .B_ADDR_SRST_N  (sresetn_rclk    ),
               // ECC-specific ports (BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_ram_wrapper wraps BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO_ram_wrapper
               // connected to the DATA_IN/OUT ECC wrapper chain)
               .DATA_IN        (DATA            ),      // ECC write data input
               //.DATA_OUT       (RDATA_int_pf    ),      // ECC read data output (used as RDATA_int)
               .INJECT_ERR_N   (8'hFF           ),      // No error injection in normal operation
               .WR_ADDR        (fifo_MEMWADDR   ),      // ECC write address
               .RD_ADDR        (ram_raddr       ),      // ECC read address
               .RD_EN          (fifo_MEMRE_int  ),      // ECC read enable
               .WR_EN          (fifo_MEMWE      ),      // ECC write enable
               .WR_CLK         (WCLOCK          ),      // ECC write clock
               .RD_CLK         (RCLOCK          ),      // ECC read clock
               .RD_PL_SRST_N   (sresetn_rclk    ),      // ECC read pipeline sync reset
               .RD_PL_ARST_N   (aresetn_rclk    ),      // ECC read pipeline async reset
               .RD_PL_EN       (1'b1            ),      // ECC read pipeline enable — always on
               .BUSY_FB        (1'b0            ),      // ECC busy feedback — not used
               .SLEEP_N        (1'b1            ),      // ECC sleep — deasserted (active)
               .ACCESS_BUSY    (                )       // ECC access busy — not used (output, leave open)
            );
			end 
        end
    end
endgenerate

generate
   always @(*) begin
      case (FAMILY)
         19, 24, 25: begin
            if (CTRL_TYPE == 2)
               RDATA_int_ram_gen_3_4_5 = RD;
            else
               RDATA_int_ram_gen_3_4_5 = A_DOUT;
         end
         26, 27:
            RDATA_int_ram_gen_3_4_5 = R_DATA;
         default:
            RDATA_int_ram_gen_3_4_5 = 0;
      endcase
   end
endgenerate

assign RDATA_int = (FAMILY == 'd28) ? RDATA_int_ram_gen_6 : RDATA_int_ram_gen_3_4_5;

endmodule // BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO

   // --------------------------------------------------------------------------
   //                             End - of - Code
   // --------------------------------------------------------------------------
