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

module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_NstagesSync(
                  clk,
                  //rstn,
                  arstn,//added in v3.0
                  srstn,//added in v3.0
                  inp,
                  sync_out
                  );

   // --------------------------------------------------------------------------
   // PARAMETER Declaration
   // --------------------------------------------------------------------------
  parameter NUM_STAGES = 2;
  parameter ADDRWIDTH = 3;
  parameter SYNC_RESET = 0;

input clk;
//input rstn;commented in v3.0
input arstn;//added in v3.0
input srstn;//added in v3.0
input [ADDRWIDTH : 0 ] inp;
output [ADDRWIDTH : 0 ] sync_out;

//reg [WIDTH -1:0] signal_out;

reg [ADDRWIDTH : 0 ] shift_reg ;
reg [ADDRWIDTH : 0 ] shift_mem_reg [NUM_STAGES-2:0] ;


integer i;
generate 
  if(SYNC_RESET == 0) begin 

    always @ ( posedge clk or negedge arstn) 
      begin	
        if (!arstn) 
    		shift_reg <= 'h0;
    	else
    		shift_reg <= inp;
    
      end 
    
    always @ ( posedge clk or negedge arstn) 
      begin	
        if (!arstn) 
          begin
            for(i = 0; i < NUM_STAGES-1 ; i = i+1) 
              begin
    		      shift_mem_reg[i] <= 0;
              end
          end
     /// signal_out <= 'h0;
        else
          begin  
    	      for(i = 0; i < NUM_STAGES-1 ; i = i+1)
              begin 	  
    	          if(i == 0)
    	  	      shift_mem_reg[i] <= shift_reg;
    	          else 
    	  	      shift_mem_reg[i] <= shift_mem_reg[i-1];
              end 
          end
      end 
    
    assign sync_out = shift_mem_reg[NUM_STAGES-2];
  end else begin 
    // --------------------------------------------------------------------------
    // FIFO Empty behavioral issue
    // When CoreFIFO is configured in Dual Clock (asynchronous)
    //   mode with Synchronous Reset (SYNC_RESET=1), and the write clock is
    //   not yet running (tied low), the write domain gray-coded pointer
    //   (wptr_gray) remains at X. Previously, shift_reg had no synchronous
    //   reset and unconditionally sampled inp every clock edge, causing X
    //   to propagate through the synchronizer stages into the read domain
    //   (wptr_gray_sync -> wptrsync_shift -> rdiff_bus -> empty_r).
    //   This caused the EMPTY flag to incorrectly de-assert in RTL
    //   simulation even though no data was written to the FIFO.
    // Resolution: Added synchronous reset (srstn) to shift_reg in the
    //   SYNC_RESET=1 path, consistent with the async reset path (arstn)
    //   which already resets shift_reg. This ensures the first synchronizer
    //   stage is held at 0 during reset, preventing X propagation from an
    //   inactive write clock domain.
    // --------------------------------------------------------------------------
    always @ ( posedge clk) 
      begin	
        if (!srstn)
  	      shift_reg <= 'h0;
        else
  	      shift_reg <= inp;    
      end 
    
    always @ ( posedge clk) 
      begin	
        if (!srstn) 
          begin
            for(i = 0; i < NUM_STAGES-1 ; i = i+1) 
              begin
    		      shift_mem_reg[i] <= 0;
              end
          end
     /// signal_out <= 'h0;
        else
          begin  
    	      for(i = 0; i < NUM_STAGES-1 ; i = i+1)
              begin 	  
    	          if(i == 0)
    	  	      shift_mem_reg[i] <= shift_reg;
    	          else 
    	  	      shift_mem_reg[i] <= shift_mem_reg[i-1];
              end 
          end
      end 
    
    assign sync_out = shift_mem_reg[NUM_STAGES-2];

  end 
endgenerate
   
endmodule // corefifo_doubleSync

   // --------------------------------------------------------------------------
   //                             End - of - Code
   // --------------------------------------------------------------------------
