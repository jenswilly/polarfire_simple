# Exporting core axi_sys_ctrl to TCL
# Exporting Create HDL core command for module axi_sys_ctrl
create_hdl_core -file "$repo_root/hdl/axi_sys_ctrl.vhd" -module {axi_sys_ctrl} -library {work} -package {}
# Exporting BIF information of  HDL core command for module axi_sys_ctrl
hdl_core_add_bif -hdl_core_name {axi_sys_ctrl} -bif_definition {AXI4:AMBA:AMBA4:slave} -bif_name {BIF_1} -signal_map {\
"AWADDR:AWADDR" \
"AWPROT:AWPROT" \
"AWVALID:AWVALID" \
"AWREADY:AWREADY" \
"WDATA:WDATA" \
"WSTRB:WSTRB" \
"WVALID:WVALID" \
"WREADY:WREADY" \
"BRESP:BRESP" \
"BVALID:BVALID" \
"BREADY:BREADY" \
"ARADDR:ARADDR" \
"ARPROT:ARPROT" \
"ARVALID:ARVALID" \
"ARREADY:ARREADY" \
"RDATA:RDATA" \
"RRESP:RRESP" \
"RVALID:RVALID" \
"RREADY:RREADY" }
