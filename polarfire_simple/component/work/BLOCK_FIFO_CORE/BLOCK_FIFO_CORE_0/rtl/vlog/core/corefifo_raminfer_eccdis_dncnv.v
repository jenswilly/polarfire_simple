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

module BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv #(
  parameter W_DWIDTH    = 128,    
  parameter W_MEM_SIZE  = 4096,
  parameter W_ADDRWIDTH = 12,
  parameter R_DWIDTH    = 64,
  parameter R_MEM_SIZE  = 8192,
  parameter R_ADDRWIDTH = 13,
  parameter RAM_SEL     = 2,
  parameter RAM_OPT     = 1,
  parameter PIPE        = 2
  )(
  input  wire w_clk,
  input  wire r_clk,
  input  wire w_en,
  input  wire r_en,
  input  wire [W_ADDRWIDTH:0] w_addr,
  input  wire [R_ADDRWIDTH:0] r_addr,
  input  wire [W_DWIDTH-1:0] w_data,
  output wire [R_DWIDTH-1:0] r_data,
  input  wire aresetn,
  input  wire sresetn
  );
  generate
    // LSRAM Instance--------------------------------------------------------------------
    if((RAM_OPT == 1) &&(RAM_SEL == 2)) // LSRAM with Low Power
    begin  : txbuf_lsram_low_power
      BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv_lsram_lp #(
        .W_DWIDTH      ( W_DWIDTH ),
        .W_MEM_SIZE    ( W_MEM_SIZE ),
        .W_ADDRWIDTH   ( W_ADDRWIDTH ),
        .R_DWIDTH      ( R_DWIDTH ),
        .R_MEM_SIZE    ( R_MEM_SIZE ),
        .R_ADDRWIDTH   ( R_ADDRWIDTH ),
        .PIPE          ( PIPE )
        ) corefifo_raminfer_eccdis_dncnv_lsram_lp_inst (
        .w_clk  ( w_clk ),
        .r_clk  ( r_clk ),
        .w_en   ( w_en ),
        .r_en   ( r_en ),
        .w_addr ( w_addr ),
        .r_addr ( r_addr ),
        .w_data ( w_data ),
        .r_data ( r_data ),
        .aresetn( aresetn ),
        .sresetn( sresetn )
      );
      end
    else if((RAM_OPT == 0) &&(RAM_SEL == 2)) // LSRAM with High Speed
    begin  : txbuf_lsram_high_speed
      BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv_lsram_hs #(
        .W_DWIDTH      ( W_DWIDTH ),
        .W_MEM_SIZE    ( W_MEM_SIZE ),
        .W_ADDRWIDTH   ( W_ADDRWIDTH ),
        .R_DWIDTH      ( R_DWIDTH ),
        .R_MEM_SIZE    ( R_MEM_SIZE ),
        .R_ADDRWIDTH   ( R_ADDRWIDTH ),
        .PIPE          ( PIPE )
        ) corefifo_raminfer_eccdis_dncnv_lsram_hs_inst (
        .w_clk         ( w_clk ),
        .r_clk         ( r_clk ),
        .w_en          ( w_en ),
        .r_en          ( r_en ),
        .w_addr        ( w_addr ),
        .r_addr        ( r_addr ),
        .w_data        ( w_data ),
        .r_data        ( r_data ),
        .aresetn       ( aresetn ),
        .sresetn       ( sresetn )
      );
      end
	  //---------------------------------------------------------------------------------
	  // USRAM Instance------------------------------------------------------------------
      else if((RAM_OPT == 1) &&(RAM_SEL == 3))  // USRAM with Low Power
      begin : txbuf_uram_low_power
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv_usram_lp #(
          .W_DWIDTH      ( W_DWIDTH ),
          .W_MEM_SIZE    ( W_MEM_SIZE ),
          .W_ADDRWIDTH   ( W_ADDRWIDTH ),
          .R_DWIDTH      ( R_DWIDTH ),
          .R_MEM_SIZE    ( R_MEM_SIZE ),
          .R_ADDRWIDTH   ( R_ADDRWIDTH ),
          .PIPE          ( PIPE )
          ) corefifo_raminfer_eccdis_dncnv_usram_lp_inst (
          .w_clk  ( w_clk ),
          .r_clk  ( r_clk ),
          .w_en   ( w_en ),
          .r_en   ( r_en ),
          .w_addr ( w_addr ),
          .r_addr ( r_addr ),
          .w_data ( w_data ),
          .r_data ( r_data ),
          .aresetn( aresetn ),
          .sresetn( sresetn )
        );
        end
      else if((RAM_OPT == 0) &&(RAM_SEL == 3))   // USRAM with High Speed
      begin : txbuf_uram_high_speed
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv_usram_hs #(
          .W_DWIDTH      ( W_DWIDTH ),
          .W_MEM_SIZE    ( W_MEM_SIZE ),
          .W_ADDRWIDTH   ( W_ADDRWIDTH ),
          .R_DWIDTH      ( R_DWIDTH ),
          .R_MEM_SIZE    ( R_MEM_SIZE ),
          .R_ADDRWIDTH   ( R_ADDRWIDTH ),
          .PIPE          ( PIPE )
          ) corefifo_raminfer_eccdis_dncnv_usram_hs_inst (
          .w_clk  ( w_clk ),
          .r_clk  ( r_clk ),
          .w_en   ( w_en ),
          .r_en   ( r_en ),
          .w_addr ( w_addr ),
          .r_addr ( r_addr ),
          .w_data ( w_data ),
          .r_data ( r_data ),
          .aresetn( aresetn ),
          .sresetn( sresetn )
        );
        end
		//-------------------------------------------------------------------------------
        else begin : txbuf_reg
        BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_corefifo_raminfer_eccdis_dncnv_reg #( //FPGA Resources
          .W_DWIDTH( W_DWIDTH ),
          .W_MEM_SIZE ( W_MEM_SIZE ),
          .W_ADDRWIDTH ( W_ADDRWIDTH ),
          .R_DWIDTH ( R_DWIDTH ),
          .R_MEM_SIZE ( R_MEM_SIZE ),
          .R_ADDRWIDTH ( R_ADDRWIDTH ),
          .PIPE ( PIPE )
          ) u_c1588b_buff_dncnv_lut (
          .w_clk  ( w_clk ),
          .r_clk  ( r_clk ),
          .w_en   ( w_en ),
          .r_en   ( r_en ),
          .w_addr ( w_addr ),
          .r_addr ( r_addr ),
          .w_data ( w_data ),
          .r_data ( r_data ),
          .aresetn( aresetn ),
          .sresetn( sresetn )
        );
        end
      endgenerate
endmodule
