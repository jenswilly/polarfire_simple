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

`timescale 1 ns / 100 ps

module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_sync (
                      clk,
                      //reset,
					  aresetn,
					  sresetn,					  
                      we,
                      re,
                      re_top,
                      empty_top_fwft,
                      full,
                      afull,
                      afull_in_dyn_thold,
                      wrcnt,
                      empty,
                      aempty,
                      aempty_in_dyn_thold,
                      rdcnt,
                      underflow,
                      overflow,
                      dvld,
                      wack,
                      memwaddr,
                      memwe,
                      memraddr,
                      memre
                      );

   // --------------------------------------------------------------------------
   // PARAMETER Declaration
   // --------------------------------------------------------------------------
   parameter AE_DYN_EN        = 1;
   parameter AF_DYN_EN        = 1;
   parameter WRITE_WIDTH      = 32;
   parameter WRITE_DEPTH      = 10;
   parameter FULL_WRITE_DEPTH = 1024;
   parameter READ_WIDTH       = 32;
   parameter READ_DEPTH       = 10;
   parameter VAR_ASPECT_WRDEPTH = 10;
   parameter VAR_ASPECT_RDDEPTH = 10;
   parameter FULL_READ_DEPTH  = 1024;
   parameter PREFETCH         = 0;  
   parameter FWFT             = 0; 
   parameter WCLK_HIGH        = 1;
   parameter RESET_LOW        = 1;
   parameter WRITE_LOW        = 1;
   parameter READ_LOW         = 1;
   parameter AF_FLAG_STATIC   = 1;
   parameter AE_FLAG_STATIC   = 1;
   parameter AFULL_VAL        = 1020;
   parameter AEMPTY_VAL       = 4;
   parameter ESTOP            = 1;
   parameter FSTOP            = 1;
   parameter PIPE             = 1;
   parameter REGISTER_RADDR   = 1;
   parameter READ_DVALID      = 32;
   parameter WRITE_ACK        = 32;
   parameter OVERFLOW_EN      = 1; 
   parameter UNDERFLOW_EN     = 1; 
   parameter WRCNT_EN         = 1; 
   parameter RDCNT_EN         = 1; 
   parameter SYNC_RESET       = 0;//uncommented in v3.0
   localparam WDEPTH_CAL      = (WRITE_DEPTH == 0) ? WRITE_DEPTH : (WRITE_DEPTH-1); 
   localparam RDEPTH_CAL      = (READ_DEPTH == 0)  ? READ_DEPTH  : (READ_DEPTH-1); 

     // --------------------------------------------------------------------------
   // I/O Declaration
   // --------------------------------------------------------------------------
   
   //--------
   // Inputs
   //--------
    input                    clk;                  // fifo clock
    //input                   reset;                // reset
    input                     aresetn;
    input                     sresetn;		
    input                    we;                   // write enable to fifo
    input                    re;                   // read enable to fifo
    input                    re_top;
    input                    empty_top_fwft;	

   //---------
   // Outputs
   //---------
   output                    full;                 // full status flag
   output                    afull;                // almost full status flag
   input  [WRITE_DEPTH-1:0]  afull_in_dyn_thold;   // almost full dynamic threshold status flag
   output [WRITE_DEPTH:0]    wrcnt;                // number of elements remaining in write domain

   output                    empty;                // empty status flag
   output                    aempty;               // almost empty status flag
   input  [READ_DEPTH-1:0]   aempty_in_dyn_thold;  // almost empty dynamic threshold status flag
   output [READ_DEPTH:0]     rdcnt;                // number of elements remaining in read domain

   output                    underflow;            // underflow status flag
   output                    overflow;             // overflow status flag
   output                    dvld;                 // dvld status flag
   output                    wack;                 // wack status flag

   output [WDEPTH_CAL:0]     memwaddr;             // memory write address
   output                    memwe;                // memory write enable
   output [RDEPTH_CAL:0]     memraddr;             // memory read address
   output                    memre;                // memory read enable

   // --------------------------------------------------------------------------
   // Internal signals
   // --------------------------------------------------------------------------
   wire                     full;
   wire                     afull;
   wire   [WRITE_DEPTH:0]   wrcnt;
   wire                     empty;
   wire                     aempty;
   wire   [READ_DEPTH:0]    rdcnt;
   wire   [WDEPTH_CAL:0]    memwaddr;
   wire                     memwe;
   wire   [RDEPTH_CAL:0]    memraddr;
   wire                     memre;
   wire                     re_top_p;

   reg                      empty_top_fwft_r;
   reg                      full_r;
  // reg                      full_reg;
   reg                      afull_r;
   reg    [WRITE_DEPTH:0]   wrcnt_r;
   reg                      empty_r;
   reg                      aempty_r;
   reg    [READ_DEPTH:0]    rdcnt_r;
   reg    [WDEPTH_CAL:0]    memwaddr_r;
   reg    [RDEPTH_CAL:0]    memraddr_r;
   reg                      dvld_r;
   reg                      dvld_r2;
   reg                      underflow_r;
   reg    [READ_DEPTH:0]    sc_r_fwft;
   reg                      empty_r_fwft;
   reg                      aempty_r_fwft;
   reg                      wack_r;
   reg                      overflow_r;
   //reg    [READ_DEPTH:0]    rptr;
   reg    [READ_DEPTH:0]    rptr_nxt;
  // reg    [WRITE_DEPTH:0]   wptr;
   reg    [WRITE_DEPTH:0]   wptr_nxt;
   wire    [READ_DEPTH:0]    sc_r_fwft_cmb;
   reg    [VAR_ASPECT_WRDEPTH:0]   wptrsync_shift; 
   reg    [VAR_ASPECT_RDDEPTH:0]   rptrsync_shift; 
  // reg                      re_p_d1;

   wire   [WRITE_DEPTH:0]   afthreshi, wdiff_bus;
   wire   [READ_DEPTH:0]    aethreshi, rdiff_bus;
   wire                     fulli;
   wire                     almostfulli;
   wire                     almostfulli_assert;
   wire                     almostfulli_deassert;
   wire                     emptyi_fwft;
   wire                     emptyi;
   reg                      almostemptyi;
   wire                     almostemptyi_assert;
   wire                     almostemptyi_deassert;
   wire                     we_p;
   wire                     re_p;
   wire                     we_i;
   wire                     re_i;
   wire                     pos_clk;
   wire                     neg_reset;
   wire                     fulli_fstop;   
   wire                     emptyi_estop; 
   wire                     aresetn;
   wire                     sresetn;//uncommented in v3.0

   wire [WRITE_DEPTH : 0]   wptr_cmb;   
   wire [READ_DEPTH : 0]   rptr_cmb; 
   // --------------------------------------------------------------------------
   // ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
   // ||                                                                      ||
   // ||                     Start - of - Code                                ||
   // ||                                                                      ||
   // ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
   // --------------------------------------------------------------------------

   // --------------------------------------------------------------------------
   // Top-level outputs
   // --------------------------------------------------------------------------
    assign full      = full_r;
    assign afull     = afull_r;
    assign empty     = empty_r;
    assign aempty    = aempty_r;
    assign underflow = underflow_r;
    assign wack      = wack_r;
    assign overflow  = overflow_r;
    assign memwaddr  = memwaddr_r;
    assign memraddr  = memraddr_r;
    
    assign wrcnt     = wrcnt_r;
    assign rdcnt     = rdcnt_r;

   // --------------------------------------------------------------------------
   // threshold values
   // --------------------------------------------------------------------------
    assign afthreshi =  AF_FLAG_STATIC ? AFULL_VAL-1  : AF_DYN_EN ? afull_in_dyn_thold-1 : FULL_WRITE_DEPTH;
    //***HARI***assign aethreshi =  AE_FLAG_STATIC ? AEMPTY_VAL+1 : 0;
    assign aethreshi =  AE_FLAG_STATIC ? AEMPTY_VAL : AE_DYN_EN ? aempty_in_dyn_thold : 2;

   // --------------------------------------------------------------------------
   // clocks and enables
   // --------------------------------------------------------------------------
    assign pos_clk   = WCLK_HIGH ? clk    : ~clk;

   // --------------------------------------------------------------------------
   // resets
   // --------------------------------------------------------------------------
/*    // assign neg_reset = RESET_LOW ? ~reset : reset;----------------------commented by anurag
	  assign aresetn = RESET_LOW ? ~reset : reset;//----------------------updated by anurag
   // assign aresetn   = (SYNC_RESET == 1) ? 1'b1  : neg_reset;-----------commented by anurag
   // assign sresetn   = (SYNC_RESET == 1) ? neg_reset : 1'b1;------------commented by anurag */

	//assign neg_reset = RESET_LOW ? ~reset : reset;//uncommented in v3.0
	//
    //assign aresetn   = (SYNC_RESET == 1) ? 1'b1  : neg_reset;//uncommented in v3.0
    //assign sresetn   = (SYNC_RESET == 1) ? neg_reset : 1'b1;//uncommented in v3.0
   // --------------------------------------------------------------------------
   // Status flags
   // --------------------------------------------------------------------------
    //assign we_p  = WRITE_LOW ? (~we) : (we);
    //assign re_p  = READ_LOW  ? (~re) : (re);
    assign we_i  = we_p & !full_r;
    assign re_i  = re_p & !empty_r;
    //assign wdiff_bus = wptr_nxt - rptrsync_shift;
    assign wdiff_bus = wptr_cmb - rptrsync_shift;
    //assign rdiff_bus = wptrsync_shift - rptr_nxt;
    assign rdiff_bus = wptrsync_shift - rptr_cmb;
    assign dvld      = (REGISTER_RADDR==2) ? dvld_r2 : 
	               ((REGISTER_RADDR == 1 && PREFETCH == 0) ? dvld_r : re_i);
				   
   generate  
      if (FWFT == 0 && PREFETCH == 0)  begin
         assign re_p     = READ_LOW  ? (~re) : (re);
         assign we_p     = WRITE_LOW ? (~we) : (we);
         assign re_top_p = re_p;
      end
      else if ((FWFT == 1 || PREFETCH == 1) && PIPE != 0)  begin
         assign re_p     = re;
         assign re_top_p = READ_LOW  ? (~re_top) : (re_top);
         assign we_p     = WRITE_LOW ? (~we) : (we);
      end
   endgenerate				   

/*     always @(posedge pos_clk or negedge aresetn)
    begin
        if (!aresetn | !sresetn ) begin
            full_reg <= 0;
        end
        else begin
            full_reg <= full_r;
        end
    end
 */
   // --------------------------------------------------------------------------
   // Read pointer binary counter
   // --------------------------------------------------------------------------
   /*  always @(posedge pos_clk or negedge aresetn)
    begin
        if (!aresetn | !sresetn ) begin
            rptr <= 0;
        end
        else begin
            rptr <=  rptr_nxt;
        end
    end */

   // --------------------------------------------------------------------------
   // Write pointer binary counter
   // --------------------------------------------------------------------------
/*     always @(posedge pos_clk or negedge aresetn)
    begin
        if (!aresetn | !sresetn ) begin
            wptr <= 0;
        end
        else begin
            wptr <= wptr_nxt;
        end
    end */

/*     always @(posedge pos_clk or negedge aresetn)
    begin
      if(!aresetn | !sresetn ) begin
        re_p_d1 <= 'h0;
      end
      else begin
        re_p_d1 <= re_p;
      end
    end  */

   // --------------------------------------------------------------------------
   // For variable aspect ratios
   // The variable aspect logic is handled by shifting the required bits of the
   // read/write pointer so that they are of the same width.  
   // --------------------------------------------------------------------------    
    always @(rptr_nxt or wptr_nxt)
    begin
       if (WRITE_DEPTH > READ_DEPTH) begin
            rptrsync_shift = rptr_nxt<<(WRITE_DEPTH - READ_DEPTH);
            wptrsync_shift = wptr_nxt>>(WRITE_DEPTH - READ_DEPTH);
       end
       else if (READ_DEPTH > WRITE_DEPTH) begin
            rptrsync_shift = rptr_nxt>>(READ_DEPTH - WRITE_DEPTH);
            wptrsync_shift = wptr_nxt<<(READ_DEPTH - WRITE_DEPTH);
       end
       else begin
            rptrsync_shift = rptr_nxt;
            wptrsync_shift = wptr_nxt;
       end
    end

   assign emptyi_fwft  =  ( sc_r_fwft  == 'h0);  

    always @(posedge pos_clk or negedge aresetn)
    begin
        if (!aresetn | !sresetn) begin
            empty_r_fwft  <= 1'b1;
            aempty_r_fwft <= 1'b1;
        end
        else begin

         //   if (we_i ^ re_i)
           //     empty_r <= emptyi;

            if (we_i ^  ((re_top_p &  empty_top_fwft & !empty_top_fwft_r)|| (re_top_p & !empty_top_fwft)))  
                empty_r_fwft <= emptyi_fwft;

            if ((we_i ^ (re_top_p &  !empty_r_fwft)))
              aempty_r_fwft <= almostemptyi;

        end
    end

   // AFULL - FWFT uses sc_r_fwft counter, standard uses wdiff_bus > afthreshi
   generate
      if ((FWFT == 1 || PREFETCH == 1) && PIPE != 0) begin : gen_afull_fwft

         // FWFT path
         always @(negedge aresetn or posedge pos_clk)
           begin
              if (!aresetn | !sresetn) begin
                 sc_r_fwft <= 0;
              end
              else if ( we_i ^ (re_top_p & !empty_top_fwft)) begin  
                   if(we_i == 1'b1) begin
                      sc_r_fwft <= sc_r_fwft_cmb;
                   end
                   else if(re_top_p & !empty_top_fwft) begin  
                      sc_r_fwft <= sc_r_fwft_cmb;
                   end
              end
          end

         assign sc_r_fwft_cmb = sc_r_fwft + we_i - re_top_p;

         assign almostfulli_assert   = ((sc_r_fwft >= (afthreshi-1)) & we_i & !(re_top_p & !empty_r_fwft));  
         assign almostfulli_deassert = ((sc_r_fwft <= afthreshi) & !we_i & (re_top_p & !empty_r_fwft));     
         assign almostfulli = almostfulli_assert ? 1'b1 : (almostfulli_deassert ? 1'b0 : afull_r);

      end
      else begin : gen_afull_standard

         assign almostfulli_assert   = we_p & (wdiff_bus > afthreshi);
         assign almostfulli_deassert = (wdiff_bus <= afthreshi);
         assign almostfulli = almostfulli_assert ? 1'b1 : (almostfulli_deassert ? 1'b0 : afull_r);

      end
   endgenerate   
   
   // AEMPTY - FWFT uses sc_r_fwft counter, standard uses rdiff_bus
   generate
      if ((FWFT == 1 || PREFETCH == 1) && PIPE != 0) begin : gen_aempty_fwft
         always @(posedge pos_clk or negedge aresetn)
           begin
              if (!aresetn | !sresetn) begin
                 almostemptyi <= 1'b1;
              end 
              else begin
                 if((sc_r_fwft >= aethreshi) && we_i & !re_top_p) begin
                    almostemptyi <= 1'b0;
                 end
                 else if((sc_r_fwft-1 <= aethreshi) && sc_r_fwft > 0 && !we_i & re_top_p) begin   
                    almostemptyi <= 1'b1;
                 end
              end
            end
      end
      else begin : gen_aempty_standard
         // Standard path: use rdiff_bus (read pointer difference)
         assign almostemptyi_assert   = re_p & (rdiff_bus < aethreshi);
         assign almostemptyi_deassert = (rdiff_bus >= aethreshi);
         always @(posedge pos_clk or negedge aresetn)
           begin
              if (!aresetn | !sresetn) begin
                 almostemptyi <= 1'b1;
              end 
              else begin
                 almostemptyi <= almostemptyi_assert ? 1'b1 : (almostemptyi_deassert ? 1'b0 : almostemptyi);
              end
            end
      end
   endgenerate


   //assign fulli  = we_p ? (wdiff_bus >= (FULL_WRITE_DEPTH-1)) : (wdiff_bus >= (FULL_WRITE_DEPTH));      
   assign fulli  = we_p ? (wdiff_bus > (FULL_WRITE_DEPTH-1)) : (wdiff_bus >= (FULL_WRITE_DEPTH));      
   //assign fulli_fstop  = (we_p & !full_r) ? (wdiff_bus[WRITE_DEPTH - 1:0]  == (FULL_WRITE_DEPTH-1)) :(((we_p ^ re_p) & full_r)? 1'b0 : full_r);      
   assign fulli_fstop  = (we_p & !full_r) ? (wdiff_bus > (FULL_WRITE_DEPTH -1)) :(((we_p ^ re_p) & full_r)? 1'b0 : full_r);      

   //assign emptyi = (rdiff_bus <= 1);   
   assign emptyi = (rdiff_bus < 1);   
   //assign emptyi_estop = re_p ? (rdiff_bus == 1) : (rdiff_bus <= 0); 
   assign emptyi_estop = re_p ? (rdiff_bus == 0) : (rdiff_bus <= 0); 

    always @(posedge pos_clk or negedge aresetn)
    begin
       if (!aresetn | !sresetn ) begin
           dvld_r2 <= 0;
       end
       else begin
           dvld_r2 <= dvld_r;
       end
    end

    // --------------------------------------------------------------------------    
    // Update the pointer values based in ESTOP and FSTOP parameters.
    // Generate the status flags - Empty/Full/Almost Empty/ Almost Full
    // Generate the data handshaking flags - DVLD/WACK
    // Generate error count flags - Underflow/Overflow
    // Generate write and read address signals to the external memory
    // --------------------------------------------------------------------------    
    genvar k;
    generate

           if (ESTOP == 1 && FSTOP == 1) begin
                /* ESTOP and FSTOP both are true */
                /* write pointer */
				
			assign wptr_cmb = wptr_nxt + we_i;///////////////////////////added
			assign rptr_cmb = rptr_nxt + re_i;//////////////////////////added
		
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn ) begin
                     wptr_nxt <= 0;
                  end
                  else if(we_i == 1'b1) begin
                     //wptr_nxt <=  wptr_nxt + 1;
                     wptr_nxt <=  wptr_cmb;/////////////added
                  end
              end

                /* read pointer */
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn) begin
                     rptr_nxt <= 0;
                  end
                  else if(re_i == 1'b1) begin
                     //rptr_nxt <=  rptr_nxt + 1;
                     rptr_nxt <=  rptr_cmb;/////////////added
                  end
              end
	
                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        empty_r     <= 1;
                        aempty_r    <= 1;
                        dvld_r      <= 0;
                        underflow_r <= 0;
                        rdcnt_r     <= 0;
                    end
                    else begin
                    //if((re_p & (rdiff_bus == 1))) begin 
					if((re_i & (rdiff_bus == 0))) begin 
                         empty_r   <= 1'b1;          
                    end
                    else if((!re_p & (rdiff_bus == 1))) begin
                         empty_r   <= 1'b0;          
                    end
                    else begin
                         empty_r   <= emptyi;          
                    end 

                        aempty_r <= almostemptyi;
			if(RDCNT_EN == 1) begin
                          rdcnt_r  <= rdiff_bus;
		        end

                        if (re_i == 1'b1 && READ_DVALID == 1)
                           dvld_r <= 1'b1;
                        else
                           dvld_r <= 1'b0;

                        if (re_p == 1'b1 && empty_r == 1'b1 && UNDERFLOW_EN == 1)
                           underflow_r <= 1'b1;
                        else
                           underflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn ) begin
                        full_r     <= 0;
                        afull_r    <= 0;
                        wack_r     <= 0;
                        overflow_r <= 0;
                        wrcnt_r    <= 0;
                    end
                    else begin
                        full_r   <= FSTOP ? fulli : fulli_fstop; 
                        afull_r    <= almostfulli;

			//if (full_r == 1'b0 && WRCNT_EN == 1) begin
			if ( WRCNT_EN == 1) begin
                           wrcnt_r <= wdiff_bus;
			end

                        if (we_i == 1'b1 && WRITE_ACK == 1)
                           wack_r <= 1'b1;
                        else
                           wack_r <= 1'b0;

                        if (we_p == 1'b1 && full_r == 1'b1 && OVERFLOW_EN == 1)
                           overflow_r <= 1'b1;
                        else
                           overflow_r <= 1'b0;
                        end
                end

                always @(posedge pos_clk or negedge aresetn )
                begin
                    if ( !aresetn | !sresetn ) begin
                        memwaddr_r     <= 0;
                    end
                    else begin
        	        if (we_i == 1'b1) begin
                           if(memwaddr_r == (FULL_WRITE_DEPTH-1)) begin
                              memwaddr_r <= 'h0;
       	        	   end else begin
                              memwaddr_r <= memwaddr_r + 1;
                           end
                        end
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if ( !aresetn | !sresetn ) begin
                        memraddr_r     <= 0;
                    end
                    else begin
      		         if (re_i == 1'b1) begin
                           if(memraddr_r == (FULL_READ_DEPTH-1)) begin
                             memraddr_r <= 'h0;
       	        	   end else begin
                             memraddr_r <= memraddr_r + 1;
			   end
			 end
                    end
                end

    	      assign memwe = we_i;
              assign memre = re_i;   


            end
            else if (ESTOP == 1 && FSTOP == 0) begin
                /* ESTOP is true and FSTOP is false */

                /* write pointer */
				assign wptr_cmb = wptr_nxt + we_p;
				assign rptr_cmb = rptr_nxt + re_i;				
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn) begin
                     wptr_nxt <= 0;
                  end
                  else if(we_p == 1'b1) begin
                     //wptr_nxt <=  wptr_nxt + 1;
                     wptr_nxt <=  wptr_cmb;
                  end
              end

                /* read pointer */
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn ) begin
                     rptr_nxt <= 0;
                  end
                  else if(re_i == 1'b1) begin
                     //rptr_nxt <=  rptr_nxt + 1;
                     rptr_nxt <=  rptr_cmb; 
                  end
              end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        empty_r     <= 1;
                        aempty_r    <= 1;
                        dvld_r      <= 0;
                        underflow_r <= 0;
                        rdcnt_r     <= 0;
                    end
                    else begin
                    //if((re_p & (rdiff_bus == 1))) begin  
                    if(((rdiff_bus == 0))) begin  					
                         empty_r   <= 1'b1;          
                    end
                    else if((!re_p & (rdiff_bus == 1))) begin
                         empty_r   <= 1'b0;          
                    end
                    else begin
                         empty_r   <= emptyi;          
                    end  

                        aempty_r <= almostemptyi;
			if(RDCNT_EN == 1) begin
                          rdcnt_r  <= rdiff_bus;
		        end

                        if (re_i == 1'b1 && READ_DVALID == 1'b1)
                           dvld_r <= 1'b1;
                        else
                           dvld_r <= 1'b0;

                        if (re_p == 1'b1 && empty_r == 1'b1 && UNDERFLOW_EN == 1)
                           underflow_r <= 1'b1;
                        else
                           underflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        full_r <= 0;
                        afull_r <= 0;
                        wack_r <= 0;
                        overflow_r <= 0;
                        wrcnt_r <= 0;
                    end
                    else begin
                        full_r   <= fulli_fstop;  
                        afull_r <= almostfulli;
			if(WRCNT_EN == 1) begin
                          wrcnt_r <= wdiff_bus;
		        end

                        if (we_p == 1'b1 && WRITE_ACK == 1'b1)
                           wack_r <= 1'b1;
                        else
                           wack_r <= 1'b0;

                        if (we_p == 1'b1 && full_r == 1'b1 && OVERFLOW_EN == 1)
                           overflow_r <= 1'b1;
                        else
                           overflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn )
                begin
                    if (!aresetn | !sresetn) begin
                        memwaddr_r   <= 0;
                    end
                    else begin
			if (we_p == 1'b1) begin
                           if(memwaddr_r == (FULL_WRITE_DEPTH-1)) begin
                              memwaddr_r <= 'h0;
			      end else begin
                              memwaddr_r <= memwaddr_r + 1;
                           end
                        end
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                       memraddr_r    <= 0;
                    end
                    else begin
			if (re_i == 1'b1) begin
                           if(memraddr_r == (FULL_READ_DEPTH-1)) begin
                             memraddr_r <= 'h0;
       	        	   end else begin
                             memraddr_r <= memraddr_r + 1;
                           end
                        end
                    end
                end

    	      assign memwe = we_p;
              assign memre = re_i;    
		
            end
            else if (ESTOP == 0 && FSTOP == 1) begin
                /* FSTOP is true and ESTOP is false */

                /* write pointer */
				assign wptr_cmb = wptr_nxt + we_i;
				assign rptr_cmb = rptr_nxt + re_p;
				
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn) begin
                     wptr_nxt <= 0;
                  end
                  else if(we_i == 1'b1) begin
                     wptr_nxt <=  wptr_cmb;
                  end
              end
	    
                /* read pointer */
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn) begin
                     rptr_nxt <= 0;
                  end
                  else if(re_p == 1'b1) begin
                     //rptr_nxt <=  rptr_nxt + 1;
                     rptr_nxt <=  rptr_cmb;
                  end
              end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        empty_r <= 1;
                        aempty_r <= 1;
                        dvld_r <= 0;
                        underflow_r <= 0;
                        rdcnt_r <= 0;
                    end
                    else begin
                        empty_r <= emptyi;
                        aempty_r <= almostemptyi;
			if(RDCNT_EN == 1) begin
                          rdcnt_r  <= rdiff_bus;
		        end

                        if (re_p == 1'b1 && READ_DVALID == 1'b1)
                           dvld_r <= 1'b1;
                        else
                           dvld_r <= 1'b0;

                        if ( re_p == 1'b1 && empty_r == 1'b1 && UNDERFLOW_EN == 1)
                           underflow_r <= 1'b1;
                        else
                           underflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        full_r <= 0;
                        afull_r <= 0;
                        wack_r <= 0;
                        overflow_r <= 0;
                        wrcnt_r <= 0;
                    end
                    else begin
                        full_r <= fulli;
                        afull_r <= almostfulli;

			//if (full_r == 1'b0 && WRCNT_EN == 1) begin
			if ( WRCNT_EN == 1) begin
                           wrcnt_r <= wdiff_bus;
			end

                        if (we_i ==1'b1 && WRITE_ACK == 1'b1)
                           wack_r <= 1'b1;
                        else
                           wack_r <= 1'b0;

                        if (we_p == 1'b1 && full_r == 1'b1 && OVERFLOW_EN == 1)
                           overflow_r <= 1'b1;
                        else
                           overflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn )
                begin
                    if ( !aresetn | !sresetn ) begin
                        memwaddr_r <= 0;
                    end
                    else begin
			if ( we_i == 1'b1) begin
                           if(memwaddr_r == (FULL_WRITE_DEPTH-1)) begin
                              memwaddr_r <= 'h0;
       	        	   end else begin
                              memwaddr_r <= memwaddr_r + 1;
                           end
                        end
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if ( !aresetn | !sresetn ) begin
                        memraddr_r <= 0;
                    end
                    else begin
		        if ( re_p == 1'b1) begin
                           if(memraddr_r == (FULL_READ_DEPTH-1)) begin
                              memraddr_r <= 'h0;
       	        	   end else begin
                              memraddr_r <= memraddr_r + 1;
                           end
                        end
                    end
                end

    	      assign memwe = we_i;
	      assign memre = re_p;    
	
            end
            else if (ESTOP == 0 && FSTOP == 0) begin
                /* ESTOP and FSTOP are false */

                /* write pointer */
				assign wptr_cmb = wptr_nxt + we_p;
				assign rptr_cmb = rptr_nxt + re_p;				
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn) begin
                     wptr_nxt <= 0;
                  end
                  else if(we_p == 1'b1) begin
                     //wptr_nxt <=  wptr_nxt + 1;
                     wptr_nxt <=  wptr_cmb;
                  end
              end
   
               /* read pointer */
   	      always @(posedge pos_clk or negedge aresetn)
              begin
                  if (!aresetn | !sresetn) begin
                     rptr_nxt <= 0;
                  end
                  else if(re_p == 1'b1) begin
                     //rptr_nxt <=  rptr_nxt + 1;
                     rptr_nxt <=  rptr_cmb;
                  end
              end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        empty_r <= 1;
                        aempty_r <= 1;
                        dvld_r <= 0;
                        underflow_r <= 0;
                        rdcnt_r <= 0;
                    end
                    else begin
                        empty_r <= emptyi_estop; 
                        aempty_r <= almostemptyi;
			if(RDCNT_EN == 1) begin
                          rdcnt_r  <= rdiff_bus;
		        end

                        if (re_p == 1'b1 && READ_DVALID == 1'b1)
                           dvld_r <= 1'b1;
                        else
                           dvld_r <= 1'b0;

                        if ( re_p ==1'b1 && empty_r == 1'b1 && UNDERFLOW_EN == 1)
                           underflow_r <= 1'b1;
                        else
                           underflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if (!aresetn | !sresetn) begin
                        full_r <= 0;
                        afull_r <= 0;
                        wack_r <= 0;
                        overflow_r <= 0;
                        wrcnt_r <= 0;
                    end
                    else begin
                        full_r <= fulli_fstop; 
                        afull_r <= almostfulli;
			if(WRCNT_EN == 1) begin
                          wrcnt_r <= wdiff_bus;
		        end

                        if (we_p == 1'b1 && WRITE_ACK == 1'b1)
                           wack_r <= 1'b1;
                        else
                           wack_r <= 1'b0;

                        if ( we_p == 1'b1 && full_r == 1'b1 && OVERFLOW_EN == 1)
                           overflow_r <= 1'b1;
                        else
                           overflow_r <= 1'b0;
                    end
                end

                always @(posedge pos_clk or negedge aresetn )
                begin
                    if ( !aresetn | !sresetn ) begin
                        memwaddr_r <= 0;
                    end
                    else begin
			if ( we_p == 1'b1) begin
                           if(memwaddr_r == (FULL_WRITE_DEPTH-1)) begin
                              memwaddr_r <= 'h0;
       	        	   end else begin
                              memwaddr_r <= memwaddr_r + 1;
                           end
                        end
                    end
                end

                always @(posedge pos_clk or negedge aresetn)
                begin
                    if ( !aresetn | !sresetn ) begin
                        memraddr_r <= 0;
                    end
                    else begin
			if ( re_p == 1'b1) begin
                           if(memraddr_r == (FULL_READ_DEPTH-1)) begin
                              memraddr_r <= 'h0;
       	        	   end else begin
                              memraddr_r <= memraddr_r + 1;
                           end
                        end
                    end
                end

    	      assign memwe = we_p;
	      assign memre = re_p;     
		
            end
    endgenerate

endmodule // corefifo_sync

   // --------------------------------------------------------------------------
   //                             End - of - Code
   // --------------------------------------------------------------------------
