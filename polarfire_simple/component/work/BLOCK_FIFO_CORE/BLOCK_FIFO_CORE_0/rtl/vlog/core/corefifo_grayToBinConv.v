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

module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_grayToBinConv(
                                         gray_in,
                                         bin_out
                                        );

   // --------------------------------------------------------------------------
   // Parameter Declaration
   // --------------------------------------------------------------------------
   parameter ADDRWIDTH  = 3;
  // parameter SYNC_RESET = 0;   

   // --------------------------------------------------------------------------
   // I/O Declaration
   // --------------------------------------------------------------------------

   //--------
   // Inputs
   //--------
   input [ADDRWIDTH:0]    gray_in;

   //---------
   // Outputs
   //---------
   output [ADDRWIDTH:0] bin_out;

   // --------------------------------------------------------------------------
   // Internal signals
   // --------------------------------------------------------------------------
   reg [ADDRWIDTH:0]      bin_out;   
   integer                i;
   

   // --------------------------------------------------------------------------
   //                               Start - of - Code
   // --------------------------------------------------------------------------


   // --------------------------------------------------------------------------
   // Logic to Convert the Gray code to Binary
   // --------------------------------------------------------------------------
   always @(*) begin

      bin_out[ADDRWIDTH]  = gray_in[ADDRWIDTH];      

      for(i=ADDRWIDTH;i>0;i = i-1) begin
         bin_out[i-1]     = (bin_out[i] ^ gray_in[i-1]);
      end

   end

endmodule // corefifo_grayToBinConv

// --------------------------------------------------------------------------
//                             End - of - Code
// --------------------------------------------------------------------------
