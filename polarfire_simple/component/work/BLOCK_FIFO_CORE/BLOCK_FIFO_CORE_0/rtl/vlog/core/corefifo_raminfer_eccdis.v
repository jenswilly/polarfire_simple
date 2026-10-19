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
module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis 
   (
	CLK            ,    
	WCLOCK         ,
	RCLOCK         ,
    DATA           ,
	fifo_MEMWADDR  ,
	fifo_MEMWE     ,
	fifo_MEMRE_int ,
	RDATA_int      ,
	ram_raddr      ,
	aresetn        ,
	sresetn          
   );
                                                                
   parameter  RDEPTH_CAL =  10;
   parameter  WDEPTH_CAL =  11;
   parameter  RWIDTH     =  64;                          
   parameter  WWIDTH     =  128;                          
   parameter  SYNC       =  0;                          
   parameter  ECC        =  0;                          
   parameter  FAMILY     =  28;                          
   parameter  RAM_OPT    =  1;                          
   parameter  PIPE       =  2;                          
   parameter  RAM_SEL    =  2;                          
   parameter  RDEPTH     =  1024;                          
   parameter  WDEPTH     =  2048;                                               

   input                              CLK            ;    
   input                              WCLOCK         ;
   input                              RCLOCK         ;
   input       [WWIDTH - 1 : 0]       DATA           ;
   input       [WDEPTH_CAL : 0]       fifo_MEMWADDR  ;
   input                              fifo_MEMWE     ;
   input                              fifo_MEMRE_int ;
   input       [RDEPTH_CAL : 0]       ram_raddr      ;
   output      [RWIDTH - 1 : 0]       RDATA_int      ;
   input                              aresetn        ;
   input                              sresetn        ;
   
   reg         [RDEPTH_CAL : 0]       ram_raddr_reg  ;
   reg         [RWIDTH - 1 : 0]       RDATA_ram      ;							
generate
   // ECC is disabled and Family is PolarFire and PolarFireSoC
   if (ECC == 0 && ((FAMILY == 28) || (FAMILY == 27) || (FAMILY == 26)))
   begin
	  // Write Latency == Read Latency (Aspect ratio 1:1)
      if (WWIDTH == RWIDTH)                 
      begin
      	 // SYNC == 'd1 : Single Clock (Synchronous Read and Write clocks).
         if(SYNC == 1)                          
         begin
		    // CTRL_TYPE == 'd2 : Controller with RAM1Kx18 memory (LSRAM)
            if(RAM_SEL == 2)                       
   	        begin
			   // Check for RAM_OPT (High Speed and Low Power) option
		       if (RAM_OPT == 1)
               begin 
			      // Generate LSRAM with low power feature
                  reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "lsram" syn_ramstyle = "low_power" */;    
			      //  Write and Address logic--------------------------------------------
                  always@(posedge CLK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
			      end
                  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
                  always@(posedge CLK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
   	                 // PIPE == 'd2 : Pipelined read data out for LSRAM,  Register Address logic
   	                 if(PIPE == 2)
                     begin
				        ram_raddr_reg <= ram_raddr;
                        RDATA_ram     <= mem[ram_raddr_reg];
			         end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for LSRAM, Without Register Address logic
			         // PIPE == 'd0 : Not Applicable for LSRAM 
			         else if(fifo_MEMRE_int)      
   	   	                RDATA_ram <= mem[ram_raddr];
                     end
                  end
                  //---------------------------------------------------------------------    	   	       
               
               end
               else
               begin 
                  // Generate LSRAM Only
		          reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "lsram" */; 

			      //  Write and Address logic--------------------------------------------
                  always@(posedge CLK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
			      end
                  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
				  
                  always@(posedge CLK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
   	                 // PIPE == 'd2 : Pipelined read data out for LSRAM,  Register Address logic
   	                 if(PIPE == 2)
                     begin
				        ram_raddr_reg <= ram_raddr;
                        RDATA_ram     <= mem[ram_raddr_reg];
			         end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for LSRAM, Without Register Address logic
			         // PIPE == 'd0 : Not Applicable for LSRAM 
			         else if(fifo_MEMRE_int)      
   	   	                RDATA_ram <= mem[ram_raddr];
                     end
                  end
                  //--------------------------------------------------------------------- 
                  
               end
            end 
			// CTRL_TYPE == 'd3 : Controller with RAM64x18 memory (uSRAM)
   	        else if(RAM_SEL == 3)                
   	        begin
			   // Check for RAM_OPT (High Speed and Low Power) option
		       if (RAM_OPT == 1)
               begin 
			      // Generate uSRAM with low power feature
                  reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "uram" syn_ramstyle = "low_power" */;    
			      //  Write and Address logic--------------------------------------------
                  always@(posedge CLK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
			      end
				  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
                  
                  always@(posedge CLK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
   	                 // PIPE == 'd2 : Pipelined read data out for uSRAM,  Register Address logic
   	                 if(PIPE == 2)
                     begin
				        ram_raddr_reg <= ram_raddr;
                        RDATA_ram     <= mem[ram_raddr_reg];
			         end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for uSRAM, Without Register Address logic
			         // PIPE == 'd0 : Not Applicable for uSRAM 
			         else if(fifo_MEMRE_int)      
   	   	                RDATA_ram <= mem[ram_raddr];
                     end
                  end
                  //---------------------------------------------------------------------    	   	       
               
               end
               else
               begin 
                  // Generate uSRAM Only
		          reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "uram" */; 

			      //  Write and Address logic--------------------------------------------
                  always@(posedge CLK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
			      end
                  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
				  
                  always@(posedge CLK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
   	                 // PIPE == 'd2 : Pipelined read data out for uSRAM,  Register Address logic
   	                 if(PIPE == 2)
                     begin
				        ram_raddr_reg <= ram_raddr;
                        RDATA_ram     <= mem[ram_raddr_reg];
			         end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for uSRAM, Without Register Address logic
			         // PIPE == 'd0 : Not Applicable for uSRAM 
			         else if(fifo_MEMRE_int)      
   	   	                RDATA_ram <= mem[ram_raddr];
                     end
                  end
                  //---------------------------------------------------------------------                 
               end
            end
         end
         // SYNC == 'd0 : Dual Clock (Asynchronous Read and Write clocks)
		 else
         begin
		    // CTRL_TYPE == 'd2 : Controller with RAM1Kx18 memory (LSRAM)
            if(RAM_SEL == 2)                        
   	        begin
			   // Check for RAM_OPT (High Speed and Low Power) option
		       if (RAM_OPT == 1)
               begin 
			         // Generate LSRAM with low power feature
                     reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "lsram" syn_ramstyle = "low_power" */;
                     
                  always@(posedge WCLOCK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
                  end
                  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
				  
                  always@(posedge RCLOCK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
		             // PIPE == 'd2 : Pipelined read data out for LSRAM,  Register logic
   	                 if(PIPE == 2)
                     begin
 			            ram_raddr_reg <= ram_raddr;
	                    RDATA_ram     <= mem[ram_raddr_reg];
                     end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for LSRAM, Without Register logic            
			         // PIPE == 'd0 : Not Applicable for LSRAM   	   	 
   	   	             else if(fifo_MEMRE_int)            
   	   	                RDATA_ram <= mem[ram_raddr];
                     end
                  end                  
                     
                  end    
   	   	          else
                  begin 
                        // Generate LSRAM Only			   
		                reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "lsram" */;
   	           
                     always@(posedge WCLOCK)
                     begin
			            // Write Data If Memory Write Enable is High 
   	   	                if(fifo_MEMWE)                         
   	   	                   mem[fifo_MEMWADDR] <= DATA;
                     end
                     
   				     assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
					 
                     always@(posedge RCLOCK or negedge aresetn)
                     begin
                        if(!aresetn | !sresetn)
                        begin
                           RDATA_ram     <= {RWIDTH{1'b0}};
                           ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                        end
                        else
                        begin
		                // PIPE == 'd2 : Pipelined read data out for LSRAM,  Register logic
   	                    if(PIPE == 2)
                        begin
 			               ram_raddr_reg <= ram_raddr;
	                       RDATA_ram     <= mem[ram_raddr_reg];
                        end
                        // PIPE == 'd1 : Non-pipelined/transparent read data out for LSRAM, Without Register logic            
			            // PIPE == 'd0 : Not Applicable for LSRAM   	   	 
   	   	                else if(fifo_MEMRE_int)            
   	   	                   RDATA_ram  <= mem[ram_raddr];
                        end
                     end
                end
   	        end
		 // CTRL_TYPE == 'd3 : Controller with RAM64x18 memory    (uSRAM)
   	     else if(RAM_SEL == 3)
   	     begin
		 
			   // Check for RAM_OPT (High Speed and Low Power) option
		       if (RAM_OPT == 1)
               begin 
			      // Generate uSRAM with low power feature
                  reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "uram" syn_ramstyle = "low_power" */;    
			      //  Write and Address logic--------------------------------------------
                  always@(posedge WCLOCK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
			      end
				  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
                  
                  always@(posedge RCLOCK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
   	                 // PIPE == 'd2 : Pipelined read data out for uSRAM,  Register Address logic
   	                 if(PIPE == 2)
                     begin
				        ram_raddr_reg <= ram_raddr;
                        RDATA_ram     <= mem[ram_raddr_reg];
			         end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for uSRAM, Without Register Address logic
			         // PIPE == 'd0 : Not Applicable for uSRAM 
			         else if(fifo_MEMRE_int)      
   	   	                RDATA_ram <= mem[ram_raddr];
                     end
                  end
                  //---------------------------------------------------------------------    	   	       
               
               end
               else
               begin 
                  // Generate uSRAM Only
		          reg [RWIDTH-1:0] mem [RDEPTH-1:0]  /* synthesis syn_ramstyle = "uram" */; 

			      //  Write and Address logic--------------------------------------------
                  always@(posedge WCLOCK)
                  begin
			         // Write Data If Memory Write Enable is High 
   	   	             if(fifo_MEMWE)                         
   	   	                mem[fifo_MEMWADDR] <= DATA;
			      end
				  
				  assign RDATA_int = (PIPE == 0) ? mem[ram_raddr] : RDATA_ram;
				  
                  
                  always@(posedge RCLOCK or negedge aresetn)
                  begin
                     if(!aresetn | !sresetn)
                     begin
                        RDATA_ram     <= {RWIDTH{1'b0}};
                        ram_raddr_reg <= {(RDEPTH_CAL+1){1'b0}};
                     end
                     else
                     begin
   	                 // PIPE == 'd2 : Pipelined read data out for uSRAM,  Register Address logic
   	                 if(PIPE == 2)
                     begin
				        ram_raddr_reg <= ram_raddr;
                        RDATA_ram     <= mem[ram_raddr_reg];
			         end
                     // PIPE == 'd1 : Non-pipelined/transparent read data out for uSRAM, Without Register Address logic
			         // PIPE == 'd0 : Not Applicable for uSRAM 
			         else if(fifo_MEMRE_int)      
   	   	                RDATA_ram  <= mem[ram_raddr];
                     end
                  end
                  //---------------------------------------------------------------------
				end 
            end     
         end
       end 
	   // Write Latency > Read Latency (Aspect ratio 1:2, 1:4, 1:8, 1:16, 1:32)
       else if (WWIDTH > RWIDTH)
	   begin
         
		 wire [RWIDTH - 1 : 0] RDATA_dncnv;
		 
		 assign RDATA_int = RDATA_ram;
		 
         always @(*)
           RDATA_ram = RDATA_dncnv;                  
                                                     
		 if(SYNC == 1)                             
		 begin : corefifo_raminfer_eccdis_dncnv_async                           
           BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv                     
           #(                                        
              .W_DWIDTH    (WWIDTH      ),     
              .W_MEM_SIZE  (WDEPTH),     
              .W_ADDRWIDTH (WDEPTH_CAL  ),           
              .R_DWIDTH    (RWIDTH      ),           
              .R_MEM_SIZE  (RDEPTH),     
              .R_ADDRWIDTH (RDEPTH_CAL  ),           
              .RAM_SEL     (RAM_SEL     ),
              .RAM_OPT     (RAM_OPT     ),			  
              .PIPE        (PIPE        )            
           )                                         
           corefifo_raminfer_eccdis_dncnv_inst(                
              .w_clk       (CLK              ),      
              .r_clk       (CLK              ),      
              .w_en        (fifo_MEMWE       ),      
              .r_en        (fifo_MEMRE_int   ),      
              .w_addr      (fifo_MEMWADDR    ),      
              .r_addr      (ram_raddr        ),      
              .w_data      (DATA             ),      
              .r_data      (RDATA_dncnv      ),      
              .aresetn     (aresetn          ),      
              .sresetn     (sresetn          )       
           );                                        
         end                                         
		 else                                        
		 begin : corefifo_raminfer_eccdis_dncnv_sync                                     
           BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv                         
           #(                                        
              .W_DWIDTH    (WWIDTH      ),    
              .W_MEM_SIZE  (WDEPTH),    
              .W_ADDRWIDTH (WDEPTH_CAL  ),          
              .R_DWIDTH    (RWIDTH      ),          
              .R_MEM_SIZE  (RDEPTH),    
              .R_ADDRWIDTH (RDEPTH_CAL  ),          
              .RAM_SEL     (RAM_SEL     ),
              .RAM_OPT     (RAM_OPT     ),			  
              .PIPE        (PIPE        )           
           )                                        
           corefifo_raminfer_eccdis_dncnv_inst(              
              .w_clk       (WCLOCK           ),     
              .r_clk       (RCLOCK           ),     
              .w_en        (fifo_MEMWE       ),     
              .r_en        (fifo_MEMRE_int   ),     
              .w_addr      (fifo_MEMWADDR    ),     
              .r_addr      (ram_raddr        ),     
              .w_data      (DATA             ),     
              .r_data      (RDATA_dncnv      ),     
              .aresetn     (aresetn          ),     
              .sresetn     (sresetn          )      
           );                                         
         end
       end                                           
	   else                                         
	   begin
       
         wire [RWIDTH - 1 : 0] RDATA_upcnv;

         always @(*)
           RDATA_ram = RDATA_upcnv;

         assign RDATA_int = RDATA_ram;
		 
         if(SYNC == 1)                          
		 begin : corefifo_raminfer_eccdis_upcnv_async                                      
           BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_upcnv 
           #(                                            
              .W_DWIDTH    (WWIDTH      ),         
              .W_MEM_SIZE  (WDEPTH),         
              .W_ADDRWIDTH (WDEPTH_CAL  ),               
              .R_DWIDTH    (RWIDTH      ),         
              .R_MEM_SIZE  (RDEPTH),         
              .R_ADDRWIDTH (RDEPTH_CAL  ),               
              .RAM_SEL     (RAM_SEL     ),
              .RAM_OPT     (RAM_OPT     ),			  
              .PIPE        (PIPE        )                
           )                                             
           corefifo_raminfer_eccdis_upcnv_inst(                    
              .w_clk       (CLK              ),          
              .r_clk       (CLK              ),          
              .w_en        (fifo_MEMWE       ),          
              .r_en        (fifo_MEMRE_int   ),          
              .w_addr      (fifo_MEMWADDR    ),          
              .r_addr      (ram_raddr        ),          
              .w_data      (DATA             ),          
              .r_data      (RDATA_upcnv      ),          
              .aresetn     (aresetn          ),          
              .sresetn     (sresetn          )           
           );                                            
         end                                            
		 else                                            
		 begin : corefifo_raminfer_eccdis_upcnv_sync                                           
           BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_upcnv                             
           #(                                            
              .W_DWIDTH    (WWIDTH      ),         
              .W_MEM_SIZE  (WDEPTH),         
              .W_ADDRWIDTH (WDEPTH_CAL  ),               
              .R_DWIDTH    (RWIDTH      ),         
              .R_MEM_SIZE  (RDEPTH),         
              .R_ADDRWIDTH (RDEPTH_CAL  ),               
              .RAM_SEL     (RAM_SEL     ),
              .RAM_OPT     (RAM_OPT     ),               
              .PIPE        (PIPE        )                
           )                                             
           corefifo_raminfer_eccdis_upcnv_inst(                   
              .w_clk       (WCLOCK           ),          
              .r_clk       (RCLOCK           ),          
              .w_en        (fifo_MEMWE       ),          
              .r_en        (fifo_MEMRE_int   ),          
              .w_addr      (fifo_MEMWADDR    ),          
              .r_addr      (ram_raddr        ),          
              .w_data      (DATA             ),          
              .r_data      (RDATA_upcnv      ),          
              .aresetn     (aresetn          ),          
              .sresetn     (sresetn          )           
           );
         end
       end
   end
endgenerate

endmodule 