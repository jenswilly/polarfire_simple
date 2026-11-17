# Exporting core bfic_block_producer to TCL
# Exporting Create HDL core command for module bfic_block_producer
create_hdl_core -file "$repo_root/hdl/bfic_block_producer.vhd" -module {bfic_block_producer} -library {work} -package {}
# Exporting BIF information of  HDL core command for module bfic_block_producer
