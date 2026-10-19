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

module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_fwft (
                        wr_clk,
                        rd_clk,
                        clk,
                        //reset_rclk_top,
						//reset_wclk_top,
						aresetn_wclk,
						aresetn_rclk,
						sresetn_wclk,
						sresetn_rclk,
                        empty,
                        aempty,
                        rd_en,
                        fifo_rd_en,
                        fifo_empty,
                        fifo_aempty,
                        fifo_dout,
                        wr_en,
                        din,
                        fwft_dvld,
                        reg_valid,
                        dout,
                        fifo_MEMRADDR,
                        fwft_MEMRADDR
                        );

   // --------------------------------------------------------------------------
   // PARAMETER Declaration
   // --------------------------------------------------------------------------
   parameter                ECC             = 0;   // ECC | 0 - ECC Disable, 1 - Pipelined ECC, 2 - Non-pipelined ECC
   parameter                PIPE            = 2;   // Pipeline read data out
   parameter                RWIDTH          = 32;  
   parameter                RDEPTH          = 64;
   parameter                WWIDTH          = 64;
   parameter                WCLK_HIGH       = 1;
   parameter                RCLK_HIGH       = 1;
   parameter                RESET_LOW       = 1;
   parameter                WRITE_LOW       = 1;
   parameter                READ_LOW        = 0;
   parameter                PREFETCH        = 0;
   parameter                FWFT            = 1;
   parameter                SYNC            = 0;
   parameter                SYNC_RESET      = 1;//uncommented in v3.0

   localparam RDEPTH_CAL      = (RDEPTH == 0) ? RDEPTH  : (RDEPTH-1);

   // --------------------------------------------------------------------------
   // I/O Declaration
   // --------------------------------------------------------------------------

   //--------
   // Inputs
   //--------

   // Clocks and Reset
   input                  wr_clk;
   input                  rd_clk;
   input                  clk;
   //input                  reset_rclk_top;
   //input                  reset_wclk_top;
   input                  wr_en;
   input                  rd_en;
   output                 fifo_rd_en;
   input [RWIDTH-1 : 0]   fifo_dout;
   input                  fifo_empty;
   input                  fifo_aempty;
   input [WWIDTH - 1 : 0] din;
   input [RDEPTH_CAL : 0] fifo_MEMRADDR;

   input				  aresetn_rclk; //added in v3.0
   input				  aresetn_wclk;//added in v3.0
   input				  sresetn_rclk;//added in v3.0
   input				  sresetn_wclk;//added in v3.0
   //---------
   // Outputs
   //---------
   output                  empty;
   output                  aempty;
   output [RWIDTH-1 : 0]   dout;
   output                  fwft_dvld;
   output                  reg_valid;
   output [RDEPTH_CAL : 0] fwft_MEMRADDR;

  // --------------------------------------------------------------------------
   // Internal signals
   // --------------------------------------------------------------------------
   reg                     fifo_valid, dout_valid, middle_valid;

   wire [RWIDTH - 1 : 0]   fifo_dout;
   wire                    fifo_rd_en, fifo_empty;
   wire                    update_dout, update_middle;

   wire [RDEPTH_CAL : 0]   fwft_MEMRADDR;
  //reg [RDEPTH_CAL : 0]   fwft_MEMRADDR;

   reg                     fifo_empty_r;
   wire                    fwft_dvld;
   reg                     wr_p_r;
   reg                     reg_valid;
   wire                    we_p;
   reg                     we_p_r;
   wire                    re_p;
   reg                     re_p_d;
   wire                    pos_rclk;
   wire                    pos_wclk;

   reg                     empty_r;
   reg                     reg_valid_r;
   wire                    empty1;
   reg                     empty;
   reg                     update_dout_r;

   wire                    fifo_empty_pulse;
   reg                     fifo_empty_pulse_d;
   wire                    fifo_init_pulse;

   wire reset_wclk;
   wire reset_rclk;
   

   reg    [RWIDTH-1:0]  dout /*synthesis syn_preserve = 1*/;
   reg                       middle1_valid, middle2_valid, fifo_rd_en_d1, fifo_rd_en_r1;
   reg    [RWIDTH-1:0]  middle_dout, middle1_dout, middle2_dout; 


   // --------------------------------------------------------------------------
   // ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
   // ||                                                                      ||
   // ||                     Start - of - Code                                ||
   // ||                                                                      ||
   // ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
   // --------------------------------------------------------------------------

   // --------------------------------------------------------------------------
   // Clocks, resets and enables
   // --------------------------------------------------------------------------
   generate
      if(SYNC == 1) begin
         assign pos_rclk  = RCLK_HIGH ? clk  : ~clk;
         assign pos_wclk  = WCLK_HIGH ? clk  : ~clk;
      end
   endgenerate

   generate
      if(SYNC == 0) begin
         assign pos_rclk  = RCLK_HIGH ? rd_clk  : ~rd_clk;
         assign pos_wclk  = WCLK_HIGH ? wr_clk  : ~wr_clk;
      end
   endgenerate

   assign we_p  = WRITE_LOW ? (~wr_en) : (wr_en);
   assign re_p  = READ_LOW  ? (~rd_en) : (rd_en);



   // --------------------------------------------------------------------------
   // Generate addresses to the memory
   // --------------------------------------------------------------------------
   assign fwft_MEMRADDR = fifo_MEMRADDR ;

   // --------------------------------------------------------------------------
   // Generates the read enable to be given to the FIFO controller
   // fifo_rd_en: It is different from the top-level read enable
   // --------------------------------------------------------------------------
   //assign fifo_rd_en = fifo_init_pulse | re_p;

   // --------------------------------------------------------------------------
   // Generate empty/almost empty signal
   // --------------------------------------------------------------------------
   //assign empty   = !dout_valid | (!fifo_valid && !middle_valid && dout_valid & !update_dout & re_p);
   //assign empty   = fifo_empty_r; //!dout_valid ;  // change by mahesh


   assign aempty  = fifo_aempty | empty;



   //assign reset_rclk  = reset_rclk_top;commented in v3.0
   //assign reset_wclk  = reset_wclk_top;commented in v3.0

   // --------------------------------------------------------------------------
   // Register empty signal
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
         fifo_empty_r   <= 1'b0;
         //fifo_empty_r   <= fifo_empty;
         update_dout_r   <= 'h0;
      end
      else begin
         fifo_empty_r   <= fifo_empty;
         update_dout_r   <= update_dout;
      end
   end

   assign fifo_empty_pulse = fifo_empty_r & !fifo_empty;

   assign fifo_init_pulse = !fifo_empty_pulse_d & fifo_empty_pulse;

   //-----------------------------------------------------------------
   //  Register re_p signal
   //-----------------------------------------------------------------
    always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
         re_p_d   <= 1'b0;
      end else begin
         re_p_d   <= re_p;
      end
    end

   //---------------------------------------------------------------------------
   // delayed empty pulse for the genration of fifo read enable
   //--------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk  | !sresetn_rclk) begin
         fifo_empty_pulse_d   <= 1'b0;
      end
      else begin
          if (fifo_empty_pulse == 1'b1) begin
              fifo_empty_pulse_d   <= 1'b1;
          end else if (fifo_empty == 1'b0 && fifo_empty_r == 1'b0) begin
              fifo_empty_pulse_d   <= 1'b0;
          end else begin
              fifo_empty_pulse_d   <= fifo_empty_pulse_d;
          end
      end
   end

   // --------------------------------------------------------------------------
   // FWFT logic
   // --------------------------------------------------------------------------
   //assign dout = fifo_dout;

   //always @(posedge pos_rclk or negedge aresetn) begin
   //   if((!aresetn) || (!sresetn)) begin
   //       dout <= 'h0;
   //   end else begin
   //       dout <= fifo_dout;
   //   end
   //end

 
   // --------------------------------------------------------------------------
   // Generate the data valid signal
   // --------------------------------------------------------------------------
   generate
      if(FWFT == 1) begin

           assign  fwft_dvld = dout_valid;
         //assign fwft_dvld = (re_p & !empty_r);
         //assign fwft_dvld = reg_valid | re_p;
      end
   endgenerate

   generate
      if(PREFETCH == 1) begin
         assign  fwft_dvld = (re_p) & dout_valid;
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Generate the qualifying signal to sample the read data. It is also used
   // to generate the read data valid signal
   // --------------------------------------------------------------------------
   always @(*) begin
      if(re_p == 1'b1) begin
         reg_valid  = 1'b0;
      end
      else if(empty == 1'b0 && empty_r == 1'b1) begin
         reg_valid  = 1'b1;
      end
      else begin
         reg_valid  = reg_valid_r;
      end
   end

   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
         empty_r   <= 1'b0;
         reg_valid_r   <= 1'b0;
      end
      else begin
         empty_r   <= empty;
         reg_valid_r   <= reg_valid;
      end
   end

   always @(posedge pos_wclk or negedge aresetn_wclk) begin
      if(!aresetn_wclk | !sresetn_wclk) begin
         we_p_r   <= 1'b0;
      end
      else begin
         we_p_r   <= we_p;
      end
   end
   
   
generate  
if  ((PIPE == 2)&&(ECC == 1)) begin : gen_axi4s_initr_cut_through_mode_pipelined_ecc
   //Used FWFT logic from CoreFIFO

   reg              fifo_rd_en_d1;
   reg              fifo_rd_en_d2;
   reg [2:0]        fifo_rdreq_cnt;
   reg [2:0]        fifo_valid_cnt;  
   reg              pipe_reg1_valid;
   reg              pipe_reg2_valid;
   reg              pipe_reg3_valid;
   reg              pipe_reg3_1_hold;
   reg              pipe_reg3_2_hold;
   reg [RWIDTH-1:0] pipe_reg1;
   reg [RWIDTH-1:0] pipe_reg2;
   reg [RWIDTH-1:0] pipe_reg3;
 
   // --------------------------------------------------------------------------
   // Generates the read enable to be given to the FIFO controller
   // fifo_rd_en: It is different from the top-level read enable
   // --------------------------------------------------------------------------
   assign fifo_rd_en = (~fifo_empty && ((fifo_rdreq_cnt != 4) || re_p));
   
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
	    fifo_rdreq_cnt <= 0;
	  end else if(fifo_rd_en ^ (dout_valid & re_p)) begin 
	    if(fifo_rd_en)
		  fifo_rdreq_cnt <= fifo_rdreq_cnt + 1'b1;
		else 
		  fifo_rdreq_cnt <= fifo_rdreq_cnt - 1'b1;
	  end 
   end 
	    
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
	    fifo_valid_cnt <= 0;
	  end else if(fifo_valid ^ (dout_valid & re_p)) begin 
	    if(fifo_valid)
		  fifo_valid_cnt <= fifo_valid_cnt + 1'b1;
		else 
		  fifo_valid_cnt <= fifo_valid_cnt - 1'b1;
	  end 
   end     

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
	   fifo_rd_en_d1  <= 0;
	 else 
	   fifo_rd_en_d1  <= fifo_rd_en;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
	   fifo_rd_en_d2  <= 0;
	 else 
	   fifo_rd_en_d2  <= fifo_rd_en_d1;	   

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       fifo_valid  <= 1'b0;
     else 
       fifo_valid  <= fifo_rd_en_d2;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg1_valid <= 1'b0;
     else if((fifo_valid_cnt == 1) && fifo_valid && ~re_p)
       pipe_reg1_valid  <= 1'b1;
     else if((fifo_valid_cnt == 2) && fifo_valid && (re_p || pipe_reg3_valid)) 
       pipe_reg1_valid  <= 1'b1;	
     else if((fifo_valid_cnt == 2) && ~pipe_reg3_valid && ~pipe_reg2_valid && ~re_p) 
       pipe_reg1_valid  <= 1'b1;	
	 else if((fifo_valid_cnt == 3) && fifo_valid && ((re_p && pipe_reg3_1_hold) || (pipe_reg2_valid && pipe_reg3_valid)))    
       pipe_reg1_valid  <= 1'b1;
	 else if (re_p) begin  
	   if(
           ((fifo_valid_cnt == 4) && ~pipe_reg3_1_hold) || 
		   ((fifo_valid_cnt == 3) && re_p && ~pipe_reg3_valid) ||
           (((fifo_valid_cnt == 2) || (fifo_valid_cnt == 1))) ||
		   (fifo_valid_cnt == 1)
	     ) 
         pipe_reg1_valid  <= 1'b0;   
     end 
	 
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg2_valid  <= 1'b0;
     else if((fifo_valid_cnt == 2) && fifo_valid && ~re_p && ~pipe_reg3_valid) 
       pipe_reg2_valid  <= 1'b1;
     //else if((fifo_valid_cnt == 3) && fifo_valid && (~re_p || (pipe_reg3_valid && pipe_reg1_valid && ~pipe_reg3_1_hold))) 
	 else if((fifo_valid_cnt == 3) && fifo_valid && (~re_p || pipe_reg3_2_hold) && ((pipe_reg1_valid && pipe_reg3_valid)))    
       pipe_reg2_valid  <= 1'b1;	   
     else if (
	       ((fifo_valid_cnt == 4) && ~(pipe_reg1_valid && ~pipe_reg3_1_hold) && ~pipe_reg3_2_hold && re_p) ||
	       ((fifo_valid_cnt == 3) && re_p && ~(pipe_reg1_valid && ~pipe_reg3_valid)) ||
		   ((fifo_valid_cnt == 2) && fifo_valid && ~pipe_reg1_valid) ||
           (fifo_valid_cnt == 1)		   
	     )
         pipe_reg2_valid  <= 1'b0;
	 
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg3_valid <= 1'b0;
     else if((fifo_valid_cnt == 3) && fifo_valid && (~re_p || (pipe_reg1_valid && pipe_reg2_valid))) 
       pipe_reg3_valid  <= 1'b1;
     else if((fifo_valid_cnt == 2) && fifo_valid && ~re_p && pipe_reg2_valid) 
       pipe_reg3_valid  <= 1'b1;	   
     else if (re_p) begin 
	   if(
	       ((fifo_valid_cnt == 4) && ~(pipe_reg1_valid && ~pipe_reg3_1_hold) && ~(pipe_reg2_valid && ~pipe_reg3_2_hold)) ||
	       ((fifo_valid_cnt == 2) && ~pipe_reg1_valid && ~pipe_reg2_valid) ||
           ((fifo_valid_cnt == 3) && ~pipe_reg2_valid) ||
		   (fifo_valid_cnt == 1)		   
	     )
         pipe_reg3_valid  <= 1'b0;
	 end   
	 
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg3_1_hold  <= 1'b0;
	 else if(~pipe_reg3_valid)
       pipe_reg3_1_hold  <= 1'b0;  
     else if(pipe_reg3_valid & ~pipe_reg1_valid)
       pipe_reg3_1_hold  <= 1'b1;

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg3_2_hold  <= 1'b0;
	 else if(~pipe_reg3_valid)
       pipe_reg3_2_hold  <= 1'b0;  
     else if(pipe_reg3_valid & ~pipe_reg2_valid)
       pipe_reg3_2_hold  <= 1'b1;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg1  <= {RWIDTH{1'b0}};
     else if (fifo_valid && (fifo_valid_cnt == 1) && ~re_p ) 
       pipe_reg1 <= fifo_dout;
     else if((fifo_valid_cnt == 2) && fifo_valid && (re_p || pipe_reg3_valid)) 
       pipe_reg1 <= fifo_dout;
	 else if((fifo_valid_cnt == 2) && ~pipe_reg3_valid && ~pipe_reg2_valid && ~pipe_reg1_valid) 
	   pipe_reg1 <= fifo_dout;
     //else if((fifo_valid_cnt == 3) && fifo_valid && (~re_p | pipe_reg3_1_hold) && ((pipe_reg2_valid && pipe_reg3_valid)))    
	 else if((fifo_valid_cnt == 3) && fifo_valid && ~pipe_reg1_valid && ((re_p && pipe_reg3_1_hold) || (pipe_reg2_valid && pipe_reg3_valid)))    
       pipe_reg1 <= fifo_dout;	
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg2  <= {RWIDTH{1'b0}};
	 else if(~pipe_reg2_valid) begin
       if((fifo_valid_cnt == 2) && fifo_valid && ~re_p && ~pipe_reg2_valid)  
	     pipe_reg2  <= fifo_dout;  
       //else if((fifo_valid_cnt == 3) && fifo_valid && (~re_p || (pipe_reg3_valid && pipe_reg1_valid)))  
	   else if((fifo_valid_cnt == 3) && fifo_valid && (~re_p || pipe_reg3_2_hold) && ((pipe_reg1_valid && pipe_reg3_valid)))    
         pipe_reg2  <= fifo_dout;  	  
	 end 
	 
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg3  <= {RWIDTH{1'b0}};  
	 else if(~pipe_reg3_valid) begin
       if((fifo_valid_cnt == 3) && fifo_valid && (~re_p || (pipe_reg1_valid && pipe_reg2_valid))) 
	     pipe_reg3  <= fifo_dout;  	   
	   else if((fifo_valid_cnt == 2) && fifo_valid && ~re_p && pipe_reg2_valid) 
	     pipe_reg3  <= fifo_dout;  	   
	 end  
	 
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       dout_valid   <= 1'b0;
     else if(fifo_valid & ~dout_valid) 
       dout_valid  <= 1'b1;
     else if((fifo_valid_cnt == 1) & re_p & ~fifo_valid) 
       dout_valid  <= 1'b0;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
      if(!aresetn_rclk | !sresetn_rclk)
         dout <= {RWIDTH{1'b0}};
      else if(~dout_valid & fifo_valid) 
		 dout <= fifo_dout;
      else if (re_p)  		   
        case(fifo_valid_cnt)
		 4       : if(pipe_reg1_valid & ~pipe_reg3_1_hold)
		             dout <= pipe_reg1;
		           else if(pipe_reg2_valid & ~pipe_reg3_2_hold)
		             dout <= pipe_reg2;
				   else 
				     dout <= pipe_reg3;
         3       : if(pipe_reg1_valid & ~pipe_reg3_valid)
                     dout <= pipe_reg1;
                   else if(pipe_reg2_valid)
        	         dout <= pipe_reg2;
                   else 
                     dout <= pipe_reg3;				   
         2       : if(pipe_reg1_valid)  
        	         dout <= pipe_reg1;
        	       else if(pipe_reg2_valid)
        	         dout <= pipe_reg2;
				   else if(pipe_reg3_valid)
				     dout <= pipe_reg3;
				   else 
				     dout <= fifo_dout;
         1       : if(pipe_reg1_valid)
		             dout <= pipe_reg1;
		           else 
				     dout <= fifo_dout;
         default : dout <= fifo_dout;
        endcase
		
   always @(posedge pos_rclk or negedge aresetn_rclk) 
     if(!aresetn_rclk | !sresetn_rclk)
       empty   <= 1'b1;
     else if(fifo_valid & ~dout_valid)
       empty  <= 1'b0;
     else if((fifo_valid_cnt == 1) & re_p & ~fifo_valid)
       empty  <= 1'b1;
       
	   
 end 
  else if  ((PIPE == ECC) | (PIPE == 2 & ECC == 0)) begin : gen_axi4s_initr_cut_through_mode_pipelined_noecc
  
   reg [2:0]        fifo_rdreq_cnt;
   reg [2:0]        fifo_valid_cnt;  
   reg              pipe_reg1_valid;
   reg              pipe_reg2_valid;
   reg [RWIDTH-1:0] pipe_reg1;
   reg [RWIDTH-1:0] pipe_reg2;
 
   // --------------------------------------------------------------------------
   // Generates the read enable to be given to the FIFO controller
   // fifo_rd_en: It is different from the top-level read enable
   // --------------------------------------------------------------------------
   assign fifo_rd_en = (~fifo_empty && ((fifo_rdreq_cnt != 3) || re_p));
   
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
	    fifo_rdreq_cnt <= 0;
	  end else if(fifo_rd_en ^ (dout_valid & re_p)) begin 
	    if(fifo_rd_en)
		  fifo_rdreq_cnt <= fifo_rdreq_cnt + 1'b1;
		else 
		  fifo_rdreq_cnt <= fifo_rdreq_cnt - 1'b1;
	  end 
   end 
	    
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
	    fifo_valid_cnt <= 0;
	  end else if(fifo_valid ^ (dout_valid & re_p)) begin 
	    if(fifo_valid)
		  fifo_valid_cnt <= fifo_valid_cnt + 1'b1;
		else 
		  fifo_valid_cnt <= fifo_valid_cnt - 1'b1;
	  end 
   end     

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
	   fifo_rd_en_d1  <= 0;
	 else 
	   fifo_rd_en_d1  <= fifo_rd_en;

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       fifo_valid  <= 1'b0;
     else 
       fifo_valid  <= fifo_rd_en_d1;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg1_valid <= 1'b0;
     else if((fifo_valid_cnt == 1) && fifo_valid && ~re_p)
       pipe_reg1_valid  <= 1'b1;
     else if((fifo_valid_cnt == 2) && fifo_valid && (re_p | pipe_reg2_valid)) 
       pipe_reg1_valid  <= 1'b1;		 
     else if(~fifo_valid && pipe_reg2_valid && re_p && (fifo_valid_cnt == 3))  
       pipe_reg1_valid  <= 1'b1;
     else if(((fifo_valid_cnt == 2) || (fifo_valid_cnt == 3)) && re_p) 
       pipe_reg1_valid  <= 1'b0;
      
 
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg2_valid <= 1'b0;
     else if((fifo_valid_cnt == 2) && fifo_valid & ~re_p) 
       pipe_reg2_valid  <= 1'b1;
     else if(((fifo_valid_cnt == 2) && re_p && ~pipe_reg1_valid) || ((fifo_valid_cnt == 3) && re_p && ~pipe_reg1_valid)) 
       pipe_reg2_valid  <= 1'b0;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg1  <= {RWIDTH{1'b0}};
     else if (fifo_valid && (fifo_valid_cnt == 1) && ~re_p ) 
       pipe_reg1 <= fifo_dout;
     else if(fifo_valid && re_p && (fifo_valid_cnt == 2))
       pipe_reg1 <= fifo_dout;
     else if(~fifo_valid && pipe_reg2_valid && re_p && (fifo_valid_cnt == 3))
       pipe_reg1 <= fifo_dout;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg2  <= {RWIDTH{1'b0}};
     else if (fifo_valid && (fifo_valid_cnt == 2) && ~re_p && ~pipe_reg2_valid) 
	   pipe_reg2  <= fifo_dout;  
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       dout_valid   <= 1'b0;
     else if(fifo_valid & ~dout_valid) 
       dout_valid  <= 1'b1;
     else if((fifo_valid_cnt == 1) & re_p & ~fifo_valid) 
       dout_valid  <= 1'b0;
	   
   always @(posedge pos_rclk or negedge aresetn_rclk)
      if(!aresetn_rclk | !sresetn_rclk)
         dout <= {RWIDTH{1'b0}};
      else if(~dout_valid & fifo_valid) 
		 dout <= fifo_dout;
      else if (re_p)  		   
        case(fifo_valid_cnt)
         3       : if(pipe_reg1_valid)
                     dout <= pipe_reg1;
                   else 
                     dout <= pipe_reg2;				 
         2       : if(pipe_reg1_valid)  
        	         dout <= pipe_reg1;
        	       else if(~fifo_valid)
                     dout <= fifo_dout;
				   else 
        	         dout <= pipe_reg2;
          1      : dout <= fifo_dout;
         default : dout <= fifo_dout;
        endcase
		
   always @(posedge pos_rclk or negedge aresetn_rclk) 
     if(!aresetn_rclk | !sresetn_rclk)
       empty   <= 1'b1;
     else if(fifo_valid & ~dout_valid)
       empty  <= 1'b0;
     else if((fifo_valid_cnt == 1) & re_p & ~fifo_valid)
       empty  <= 1'b1;
       
 end
 // --------------------------------------------------------------------------
 // Pipelined FWFT block for PIPE=1 (ECC!=1)
 //
 // Problem: The original PIPE=1 FWFT path was fully combinational from
 //   RAM output (fifo_dout) through the FWFT data mux to the dout
 //   register, causing 130 logic levels on G6 at high frequency.
 //
 // Solution: Use the same 2-flop pipeline structure as PIPE=2
 //   (fifo_rd_en -> fifo_rd_en_d1 -> fifo_valid), but add a local data
 //   capture register (fifo_dout_r) inside the FWFT block. fifo_dout_r
 //   captures fifo_dout at the fifo_rd_en_d1 stage (when PIPE=1 RAM data
 //   is valid). All data paths (dout, pipe_reg1) use fifo_dout_r instead
 //   of fifo_dout, breaking the combinational path from RAM output.
 //
 // PIPE=1 RAM + FWFT timing:
 //   Cycle N:   fifo_rd_en=1 -> MEMRE=1, RAM captures mem[addr]
 //   Cycle N+1: RDATA_int=D0 valid (PIPE=1 registered RAM output)
 //              fifo_rd_en_d1=1 -> fifo_dout_r captures fifo_dout(=D0)
 //   Cycle N+2: fifo_valid=1 -> fifo_dout_r is stable at D0
 //              dout <= fifo_dout_r (=D0).  Correct.
 //
  // COREFIFO.v uses int_MEMRD_fwft_pipe1 / ext_MEMRD_fwft (1-cycle hold-mux)
  // for the FWFT+PIPE=1 data path. The fifo_dout_r register inside this
  // block provides the extra pipeline stage that PIPE=2 gets from the RAM.
  //
  // The only difference vs PIPE=2: PIPE=1 needs fifo_dout_r because the
  // PIPE=1 RAM output (RDATA_int) changes every cycle during continuous
  // reads (only 1 stage of RAM pipeline), whereas PIPE=2 RAM has 2 stages
  // and naturally holds data stable for the fifo_valid cycle.
 // --------------------------------------------------------------------------
 else if  ((PIPE == 1) && (ECC != 1)) begin : gen_axi4s_initr_cut_through_mode_nonpipelined

   // This block mirrors the PIPE=2 noecc structure (same counters, same
   // pipe registers, same control logic) with one addition: fifo_dout_r,
   // a data capture register that breaks the combinational path from
   // PIPE=1 RAM output to dout. All data references use fifo_dout_r
   // instead of fifo_dout.

   reg [2:0]        fifo_rdreq_cnt;
   reg [2:0]        fifo_valid_cnt;
   reg              pipe_reg1_valid;
   reg              pipe_reg2_valid;
   reg [RWIDTH-1:0] pipe_reg1;
   reg [RWIDTH-1:0] pipe_reg2;
   reg [RWIDTH-1:0] fifo_dout_r;

   // --------------------------------------------------------------------------
   // Generates the read enable to be given to the FIFO controller
   // fifo_rd_en: It is different from the top-level read enable.
   // Max in-flight = 3: pipe_reg1 + pipe_reg2 + dout.
   // --------------------------------------------------------------------------
   assign fifo_rd_en = (~fifo_empty && ((fifo_rdreq_cnt != 3) || re_p));

   // --------------------------------------------------------------------------
   // Track outstanding read requests (fifo_rd_en issued but not yet consumed)
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
        fifo_rdreq_cnt <= 0;
      end else if(fifo_rd_en ^ (dout_valid & re_p)) begin
        if(fifo_rd_en)
          fifo_rdreq_cnt <= fifo_rdreq_cnt + 1'b1;
        else
          fifo_rdreq_cnt <= fifo_rdreq_cnt - 1'b1;
      end
   end

   // --------------------------------------------------------------------------
   // Track valid data count in pipeline
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk) begin
      if(!aresetn_rclk | !sresetn_rclk) begin
        fifo_valid_cnt <= 0;
      end else if(fifo_valid ^ (dout_valid & re_p)) begin
        if(fifo_valid)
          fifo_valid_cnt <= fifo_valid_cnt + 1'b1;
        else
          fifo_valid_cnt <= fifo_valid_cnt - 1'b1;
      end
   end

   // --------------------------------------------------------------------------
   // Pipeline: fifo_rd_en -> fifo_rd_en_d1 -> fifo_valid (2 flops total)
   //
   // Stage 1 (fifo_rd_en_d1): 1 cycle after fifo_rd_en. At this point,
   //   PIPE=1 RAM data (fifo_dout) is valid. We capture it into fifo_dout_r.
   //   This breaks the combinational path from RAM output to dout.
   //
   // Stage 2 (fifo_valid): 1 cycle after fifo_rd_en_d1. At this point,
   //   fifo_dout_r is stable with the captured data. The dout mux uses
   //   fifo_dout_r (a register) instead of fifo_dout (combinational from
   //   RAM), so the path to the dout register is short.
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       fifo_rd_en_d1  <= 0;
     else
       fifo_rd_en_d1  <= fifo_rd_en;

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       fifo_valid  <= 1'b0;
     else
       fifo_valid  <= fifo_rd_en_d1;

    // --------------------------------------------------------------------------
    // Data capture register: captures fifo_dout when fifo_rd_en_d1 is active.
    // At fifo_rd_en_d1 time, PIPE=1 RAM data is valid on fifo_dout.
    // At the NEXT posedge (fifo_valid), fifo_dout_r holds the correct data
    // for this pipeline stage. This breaks the combinational path from RAM
    // output to dout, which was the root cause of the 130 logic level issue.
    // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       fifo_dout_r  <= {RWIDTH{1'b0}};
     else if(fifo_rd_en_d1)
       fifo_dout_r  <= fifo_dout;

   // --------------------------------------------------------------------------
   // Pipe register valid controls
   // Mirrors PIPE=2 noecc logic exactly, using same counter thresholds.
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg1_valid <= 1'b0;
     else if((fifo_valid_cnt == 1) && fifo_valid && ~re_p)
       pipe_reg1_valid  <= 1'b1;
     else if((fifo_valid_cnt == 2) && fifo_valid && (re_p | pipe_reg2_valid)) 
       pipe_reg1_valid  <= 1'b1;		 
     else if(~fifo_valid && pipe_reg2_valid && re_p && (fifo_valid_cnt == 3))  
       pipe_reg1_valid  <= 1'b1;
     else if(((fifo_valid_cnt == 2) || (fifo_valid_cnt == 3)) && re_p) 
       pipe_reg1_valid  <= 1'b0;

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg2_valid <= 1'b0;
     else if((fifo_valid_cnt == 2) && fifo_valid & ~re_p) 
       pipe_reg2_valid  <= 1'b1;
     else if(((fifo_valid_cnt == 2) && re_p && ~pipe_reg1_valid) || ((fifo_valid_cnt == 3) && re_p && ~pipe_reg1_valid)) 
       pipe_reg2_valid  <= 1'b0;

   // --------------------------------------------------------------------------
   // Pipe register data captures
   // Use fifo_dout_r (registered) instead of fifo_dout (combinational).
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg1  <= {RWIDTH{1'b0}};
     else if (fifo_valid && (fifo_valid_cnt == 1) && ~re_p ) 
       pipe_reg1 <= fifo_dout_r;
     else if(fifo_valid && re_p && (fifo_valid_cnt == 2))
       pipe_reg1 <= fifo_dout_r;
     else if(~fifo_valid && pipe_reg2_valid && re_p && (fifo_valid_cnt == 3))
       pipe_reg1 <= fifo_dout_r;

   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       pipe_reg2  <= {RWIDTH{1'b0}};
     else if (fifo_valid && (fifo_valid_cnt == 2) && ~re_p && ~pipe_reg2_valid) 
       pipe_reg2  <= fifo_dout_r;

   // --------------------------------------------------------------------------
   // Output data valid
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       dout_valid   <= 1'b0;
     else if(fifo_valid & ~dout_valid) 
       dout_valid  <= 1'b1;
     else if((fifo_valid_cnt == 1) & re_p & ~fifo_valid) 
       dout_valid  <= 1'b0;

   // --------------------------------------------------------------------------
   // Output data mux
   // Mirrors PIPE=2 noecc dout mux structure exactly, using fifo_dout_r
   // instead of fifo_dout. Since fifo_dout_r is unconditionally registered
   // (trails fifo_dout by exactly 1 cycle), it has the same timing
   // relationship to fifo_valid as fifo_dout has in the PIPE=2 block:
   //   - PIPE=2: fifo_dout is valid at fifo_valid (2-cycle RAM latency)
   //   - PIPE=1: fifo_dout_r is valid at fifo_valid (1-cycle RAM + 1 reg)
   //
   // All data paths are fully registered — no combinational path from
   // PIPE=1 RAM output to dout.
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
      if(!aresetn_rclk | !sresetn_rclk)
         dout <= {RWIDTH{1'b0}};
      else if(~dout_valid & fifo_valid) 
         dout <= fifo_dout_r;
      else if (re_p)  		   
        case(fifo_valid_cnt)
         3       : if(pipe_reg1_valid)
                     dout <= pipe_reg1;
                   else 
                     dout <= pipe_reg2;				 
         2       : if(pipe_reg1_valid)  
                     dout <= pipe_reg1;
                   else if(~fifo_valid)
                     dout <= fifo_dout_r;
                   else 
                     dout <= pipe_reg2;
          1      : dout <= fifo_dout_r;
         default : dout <= fifo_dout_r;
        endcase

   // --------------------------------------------------------------------------
   // Empty flag generation
   // --------------------------------------------------------------------------
   always @(posedge pos_rclk or negedge aresetn_rclk)
     if(!aresetn_rclk | !sresetn_rclk)
       empty   <= 1'b1;
     else if(fifo_valid & ~dout_valid)
       empty  <= 1'b0;
     else if((fifo_valid_cnt == 1) & re_p & ~fifo_valid)
       empty  <= 1'b1;

end
endgenerate   

endmodule // corefifo_fwft

   // --------------------------------------------------------------------------
   //                             End - of - Code
   // --------------------------------------------------------------------------

