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
module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_upcnv_usram_lp #(
  parameter W_DWIDTH    = 64,
  parameter W_MEM_SIZE  = 8192,
  parameter W_ADDRWIDTH = 13,
  parameter R_DWIDTH    = 128,
  parameter R_MEM_SIZE  = 4096,
  parameter R_ADDRWIDTH = 12,
  parameter PIPE     = 2 //0 - Asynchronous(No registering of address and data)
                         //1 - Non-pipelined(address only registerd)
                         //2 - Pipelined (both address and data are registered)
  )(
  input  wire w_clk,
  input  wire r_clk,
  input  wire w_en,
  input  wire r_en,
  input  wire [W_ADDRWIDTH:0] w_addr,
  input  wire [R_ADDRWIDTH:0] r_addr,
  input  wire [W_DWIDTH-1:0] w_data,
  output reg  [R_DWIDTH-1:0] r_data,
  input  wire aresetn,
  input  wire sresetn
  );

  function [31:0] MAX;
      input [31:0] a;
      input [31:0] b;
      begin
          if (a > b)
              MAX = a;
          else
              MAX = b;
      end
  endfunction
  function [31:0] MIN;
      input [31:0] a;
      input [31:0] b;
      begin
          if (a < b)
              MIN = a;
          else
              MIN = b;
      end
  endfunction
  localparam MAXSIZE = MAX(W_MEM_SIZE, R_MEM_SIZE);
  localparam MAXWIDTH = MAX(W_DWIDTH, R_DWIDTH);
  localparam MINWIDTH = MIN(W_DWIDTH, R_DWIDTH);
  localparam RATIO = MAXWIDTH / MINWIDTH;
  localparam LOG2RATIO = $clog2(RATIO);

  reg [R_ADDRWIDTH:0] r_addr_r;
  reg [R_DWIDTH-1:0] readb;
  reg [MINWIDTH-1:0] ram [0:MAXSIZE-1] /* synthesis syn_ramstyle = uram  syn_ramstyle = low_power */;

  always @(posedge w_clk)
  begin
    if (w_en)
      ram[w_addr] <= w_data;
  end

  generate
  if(PIPE != 0)
  begin : pipelined_address
    always @(posedge r_clk)
    begin
      if (r_en)
        r_addr_r <= r_addr;
    end
  end
  else
  begin : non_pipelined_address
    always @ (*)
	r_addr_r = r_addr;
  end
  endgenerate


  genvar i;
  generate for (i = 0; i < RATIO; i = i+1)
  begin: ramread
    localparam [LOG2RATIO-1:0] lsbaddr = i;
    always @(*)
    begin
      readb[(i+1)*MINWIDTH-1:i*MINWIDTH] = ram[{r_addr_r, lsbaddr}];
    end
  end
  endgenerate

  generate
  if (PIPE == 0)
  begin
     always @ (*)
        r_data = ram[r_addr];
  end 
  else if(PIPE == 2)
  begin : pipelined_data
    always @ (posedge r_clk or negedge aresetn)
      if(!aresetn | !sresetn)
        r_data <= {R_DWIDTH{1'b0}};
      else
        r_data <= readb;
  end
  else
  begin : non_pipelined_data
    always @ (*)
      r_data = readb;
  end
  endgenerate

endmodule
