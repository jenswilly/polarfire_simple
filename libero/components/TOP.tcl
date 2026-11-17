# Creating SmartDesign "TOP"
set sd_name {TOP}
create_smartdesign -sd_name ${sd_name}

# Disable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 0

# Create top level Scalar Ports
sd_create_scalar_port -sd_name ${sd_name} -port_name {MMUART_1_RXD} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {MMUART_4_RXD} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {REFCLK_N} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {REFCLK} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {REF_CLK_50MHz} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_CD} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SWITCH2} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {UART0_RX} -port_direction {IN}

sd_create_scalar_port -sd_name ${sd_name} -port_name {ACT_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {BG0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {CAS_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {CK0_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {CK0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {CKE0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {CS0_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {DEBUG} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED1} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED2} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED3} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED4} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED5} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED6} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {LED7} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {MBUS_QSPI_CS_N} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {MBUS_QSPI_SCLK} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {MMUART_1_TXD} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {MMUART_4_TXD} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {ODT0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {QSPI_CS_N} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {QSPI_SCLK} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {RAS_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {RESET_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {RPi_GPIO16} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {RPi_GPIO19} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {RPi_GPIO20} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {RPi_GPIO26} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_CLK} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_VOLT_CMD_DIR} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_VOLT_DIR_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_VOLT_DIR_1_3} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_VOLT_EN} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_VOLT_SEL} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {UART0_TX} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {WE_N} -port_direction {OUT} -port_is_pad {1}

sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_CMD} -port_direction {INOUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_DATA0} -port_direction {INOUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_DATA1} -port_direction {INOUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_DATA2} -port_direction {INOUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {SD_DATA3} -port_direction {INOUT} -port_is_pad {1}

# Create top level Bus Ports
sd_create_bus_port -sd_name ${sd_name} -port_name {A} -port_direction {OUT} -port_range {[13:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {BA} -port_direction {OUT} -port_range {[1:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {DM} -port_direction {OUT} -port_range {[1:0]} -port_is_pad {1}

sd_create_bus_port -sd_name ${sd_name} -port_name {DQS_N} -port_direction {INOUT} -port_range {[1:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {DQS} -port_direction {INOUT} -port_range {[1:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {DQ} -port_direction {INOUT} -port_range {[15:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {MBUS_QSPI_IO} -port_direction {INOUT} -port_range {[3:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {QSPI_IO} -port_direction {INOUT} -port_range {[3:0]}

sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {LED7} -value {GND}
# Add AND2_0 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {AND2} -instance_name {AND2_0}



# Add AXI_IC_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {AXI_IC} -instance_name {AXI_IC_0}



# Add axi_sys_ctrl_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {axi_sys_ctrl} -instance_name {axi_sys_ctrl_0}
# Exporting Parameters of instance axi_sys_ctrl_0
sd_configure_core_instance -sd_name ${sd_name} -instance_name {axi_sys_ctrl_0} -params {\
"ADDR_WIDTH:38" }\
-validate_rules 0
sd_save_core_instance_config -sd_name ${sd_name} -instance_name {axi_sys_ctrl_0}
sd_update_instance -sd_name ${sd_name} -instance_name {axi_sys_ctrl_0}



# Add bfic_block_producer_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {bfic_block_producer} -instance_name {bfic_block_producer_0}
# Exporting Parameters of instance bfic_block_producer_0
sd_configure_core_instance -sd_name ${sd_name} -instance_name {bfic_block_producer_0} -params {\
"BEAMS_PER_BFIC:4" \
"BFIC_AD3:0" }\
-validate_rules 0
sd_save_core_instance_config -sd_name ${sd_name} -instance_name {bfic_block_producer_0}
sd_update_instance -sd_name ${sd_name} -instance_name {bfic_block_producer_0}



# Add bfic_block_producer_1 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {bfic_block_producer} -instance_name {bfic_block_producer_1}
# Exporting Parameters of instance bfic_block_producer_1
sd_configure_core_instance -sd_name ${sd_name} -instance_name {bfic_block_producer_1} -params {\
"BEAMS_PER_BFIC:4" \
"BFIC_AD3:1" }\
-validate_rules 0
sd_save_core_instance_config -sd_name ${sd_name} -instance_name {bfic_block_producer_1}
sd_update_instance -sd_name ${sd_name} -instance_name {bfic_block_producer_1}



# Add block_arbiter_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {block_arbiter} -instance_name {block_arbiter_0}
# Exporting Parameters of instance block_arbiter_0
sd_configure_core_instance -sd_name ${sd_name} -instance_name {block_arbiter_0} -params {\
"BLOCK_BYTES:10" \
"NUM_PORTS:2" }\
-validate_rules 0
sd_save_core_instance_config -sd_name ${sd_name} -instance_name {block_arbiter_0}
sd_update_instance -sd_name ${sd_name} -instance_name {block_arbiter_0}
sd_create_pin_slices -sd_name ${sd_name} -pin_name {block_arbiter_0:s_data} -pin_slices {[159:80]}
sd_create_pin_slices -sd_name ${sd_name} -pin_name {block_arbiter_0:s_data} -pin_slices {[79:0]}
sd_create_pin_slices -sd_name ${sd_name} -pin_name {block_arbiter_0:s_valid} -pin_slices {[0:0]}
sd_create_pin_slices -sd_name ${sd_name} -pin_name {block_arbiter_0:s_valid} -pin_slices {[1:1]}
sd_create_pin_slices -sd_name ${sd_name} -pin_name {block_arbiter_0:s_ready} -pin_slices {[0:0]}
sd_create_pin_slices -sd_name ${sd_name} -pin_name {block_arbiter_0:s_ready} -pin_slices {[1:1]}



# Add button_debounce_0 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {button_debounce} -hdl_file "$repo_root/hdl/button_debounce.vhd" -instance_name {button_debounce_0}



# Add CLKINT_0 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {CLKINT} -instance_name {CLKINT_0}



# Add CORERESET_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {CORERESET} -instance_name {CORERESET_0}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {CORERESET_0:BANK_x_VDDI_STATUS} -value {VCC}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {CORERESET_0:BANK_y_VDDI_STATUS} -value {VCC}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {CORERESET_0:SS_BUSY} -value {GND}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {CORERESET_0:FF_US_RESTORE} -value {GND}



# Add INIT_MONITOR_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {INIT_MONITOR} -instance_name {INIT_MONITOR_0}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:PCIE_INIT_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:USRAM_INIT_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:SRAM_INIT_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:BANK_0_CALIB_STATUS}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:BANK_1_CALIB_STATUS}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:XCVR_INIT_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:USRAM_INIT_FROM_SNVM_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:USRAM_INIT_FROM_UPROM_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:USRAM_INIT_FROM_SPI_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:SRAM_INIT_FROM_SNVM_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:SRAM_INIT_FROM_UPROM_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:SRAM_INIT_FROM_SPI_DONE}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {INIT_MONITOR_0:AUTOCALIB_DONE}



# Add mss_qspi_pads_0 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {mss_qspi_pads} -hdl_file "$repo_root/hdl/mss_qspi_pads.vhd" -instance_name {mss_qspi_pads_0}



# Add MSS_simple_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {MSS_simple} -instance_name {MSS_simple_0}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {MSS_simple_0:MSS_RESET_N_F2M} -value {VCC}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {MSS_simple_0:MMUART_0_TXD_OE_M2F}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {MSS_simple_0:PLL_CPU_LOCK_M2F}
sd_mark_pins_unused -sd_name ${sd_name} -pin_names {MSS_simple_0:PLL_DDR_LOCK_M2F}



# Add OR2_1 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {OR2} -instance_name {OR2_1}



# Add PF_CCC_C0_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_CCC_C0} -instance_name {PF_CCC_C0_0}



# Add pulse_stretch_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {pulse_stretch} -instance_name {pulse_stretch_0}
# Exporting Parameters of instance pulse_stretch_0
sd_configure_core_instance -sd_name ${sd_name} -instance_name {pulse_stretch_0} -params {\
"STRETCH_CYCLES:200000" }\
-validate_rules 0
sd_save_core_instance_config -sd_name ${sd_name} -instance_name {pulse_stretch_0}
sd_update_instance -sd_name ${sd_name} -instance_name {pulse_stretch_0}



# Add qspi_board_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {qspi_board} -instance_name {qspi_board_0}
# Exporting Parameters of instance qspi_board_0
sd_configure_core_instance -sd_name ${sd_name} -instance_name {qspi_board_0} -params {\
"BLK_LEN:880" \
"CALIBRATE:1" \
"CLK_HZ:200000000" \
"DEVICE_SEL:0" \
"NBLK:8" \
"SAMPLE_DLY:4" \
"SCLK_DIV:2" }\
-validate_rules 0
sd_save_core_instance_config -sd_name ${sd_name} -instance_name {qspi_board_0}
sd_update_instance -sd_name ${sd_name} -instance_name {qspi_board_0}



# Add spi_tx_path_0 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {spi_tx_path} -hdl_file "$repo_root/hdl/spi_tx_path.vhd" -instance_name {spi_tx_path_0}



# Add scalar net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"ACT_N" "MSS_simple_0:ACT_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:A" "MSS_simple_0:MSS_RESET_N_M2F" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:B" "MSS_simple_0:FIC_0_DLL_LOCK_M2F" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:Y" "CORERESET_0:EXT_RST_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AXI_IC_0:ACLK" "CORERESET_0:CLK" "MSS_simple_0:FIC_0_ACLK" "PF_CCC_C0_0:OUT0_FABCLK_0" "axi_sys_ctrl_0:ACLK" "bfic_block_producer_0:clk" "bfic_block_producer_1:clk" "block_arbiter_0:clk" "button_debounce_0:clk" "pulse_stretch_0:clk" "qspi_board_0:clk" "spi_tx_path_0:clk" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AXI_IC_0:ARESETN" "CORERESET_0:FABRIC_RESET_N" "axi_sys_ctrl_0:ARESETN" "bfic_block_producer_0:reset_n" "bfic_block_producer_1:reset_n" "block_arbiter_0:reset_n" "button_debounce_0:reset_n" "pulse_stretch_0:reset_n" "qspi_board_0:reset_n" "spi_tx_path_0:reset_n" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"BG0" "MSS_simple_0:BG0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CAS_N" "MSS_simple_0:CAS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CK0" "MSS_simple_0:CK0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CK0_N" "MSS_simple_0:CK0_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CKE0" "MSS_simple_0:CKE0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CLKINT_0:A" "REF_CLK_50MHz" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CLKINT_0:Y" "PF_CCC_C0_0:REF_CLK_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CORERESET_0:FPGA_POR_N" "INIT_MONITOR_0:FABRIC_POR_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CORERESET_0:INIT_DONE" "INIT_MONITOR_0:DEVICE_INIT_DONE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CORERESET_0:PLL_LOCK" "PF_CCC_C0_0:PLL_LOCK_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CORERESET_0:PLL_POWERDOWN_B" "PF_CCC_C0_0:PLL_POWERDOWN_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"CS0_N" "MSS_simple_0:CS0_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DEBUG" "pulse_stretch_0:pulse_out" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"LED1" "qspi_board_0:busy_out" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"LED2" "axi_sys_ctrl_0:LED2" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"LED3" "axi_sys_ctrl_0:LED3" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"LED4" "button_debounce_0:pressed_out" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"LED5" "qspi_board_0:bist_pass" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"LED6" "qspi_board_0:bist_fail" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MBUS_QSPI_CS_N" "mss_qspi_pads_0:qspi_cs_n" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MBUS_QSPI_SCLK" "mss_qspi_pads_0:qspi_sclk" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MMUART_1_RXD" "MSS_simple_0:MMUART_1_RXD" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MMUART_1_TXD" "MSS_simple_0:MMUART_1_TXD" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MMUART_4_RXD" "MSS_simple_0:MMUART_4_RXD" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MMUART_4_TXD" "MSS_simple_0:MMUART_4_TXD" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:MMUART_0_RXD_F2M" "UART0_RX" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:MMUART_0_TXD_M2F" "UART0_TX" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:ODT0" "ODT0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_CLK_M2F" "mss_qspi_pads_0:mss_qspi_clk" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_CLK_OE_M2F" "mss_qspi_pads_0:mss_qspi_clk_oe" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_SEL_M2F" "mss_qspi_pads_0:mss_qspi_sel" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_SEL_OE_M2F" "mss_qspi_pads_0:mss_qspi_sel_oe" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:RAS_N" "RAS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:REFCLK" "REFCLK" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:REFCLK_N" "REFCLK_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:RESET_N" "RESET_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_CD" "SD_CD" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_CLK" "SD_CLK" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_CMD" "SD_CMD" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_DATA0" "SD_DATA0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_DATA1" "SD_DATA1" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_DATA2" "SD_DATA2" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_DATA3" "SD_DATA3" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_VOLT_CMD_DIR" "SD_VOLT_CMD_DIR" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_VOLT_DIR_0" "SD_VOLT_DIR_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_VOLT_DIR_1_3" "SD_VOLT_DIR_1_3" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_VOLT_EN" "SD_VOLT_EN" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:SD_VOLT_SEL" "SD_VOLT_SEL" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:WE_N" "WE_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"OR2_1:A" "button_debounce_0:pulse_out" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"OR2_1:B" "axi_sys_ctrl_0:DEBUG_PULSE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"OR2_1:Y" "bfic_block_producer_0:start_in" "bfic_block_producer_1:start_in" "pulse_stretch_0:pulse_in" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"QSPI_CS_N" "qspi_board_0:qspi_cs_n" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"QSPI_SCLK" "qspi_board_0:qspi_sclk" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"RPi_GPIO16" "spi_tx_path_0:spi_mosi" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"RPi_GPIO19" "spi_tx_path_0:spi_sclk" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"RPi_GPIO20" "spi_tx_path_0:busy_out" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"RPi_GPIO26" "spi_tx_path_0:spi_cs_n" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"SWITCH2" "button_debounce_0:btn_in" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"bfic_block_producer_0:m_ready" "block_arbiter_0:s_ready[0:0]" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"bfic_block_producer_0:m_valid" "block_arbiter_0:s_valid[0:0]" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"bfic_block_producer_1:m_ready" "block_arbiter_0:s_ready[1:1]" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"bfic_block_producer_1:m_valid" "block_arbiter_0:s_valid[1:1]" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"block_arbiter_0:m_ready" "spi_tx_path_0:s_ready" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"block_arbiter_0:m_valid" "spi_tx_path_0:s_valid" }

# Add bus net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"A" "MSS_simple_0:A" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"BA" "MSS_simple_0:BA" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DM" "MSS_simple_0:DM" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DQ" "MSS_simple_0:DQ" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DQS" "MSS_simple_0:DQS" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DQS_N" "MSS_simple_0:DQS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MBUS_QSPI_IO" "mss_qspi_pads_0:qspi_io" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_DATA_F2M" "mss_qspi_pads_0:mss_qspi_data_i" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_DATA_M2F" "mss_qspi_pads_0:mss_qspi_data_o" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"MSS_simple_0:QSPI_DATA_OE_M2F" "mss_qspi_pads_0:mss_qspi_data_oe" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"QSPI_IO" "qspi_board_0:qspi_io" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"bfic_block_producer_0:m_data" "block_arbiter_0:s_data[79:0]" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"bfic_block_producer_1:m_data" "block_arbiter_0:s_data[159:80]" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"block_arbiter_0:m_data" "spi_tx_path_0:s_data" }

# Add bus interface net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"AXI_IC_0:AXI4Lmtarget0" "axi_sys_ctrl_0:BIF_1" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AXI_IC_0:AXI4minitiator0" "MSS_simple_0:FIC_0_AXI4_INITIATOR" }

# Re-enable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 1
# Save the SmartDesign 
save_smartdesign -sd_name ${sd_name}
# Generate SmartDesign "TOP"
generate_component -component_name ${sd_name}
