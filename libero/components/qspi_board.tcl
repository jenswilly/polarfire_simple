# Exporting core qspi_board to TCL
# Exporting Create HDL core command for module qspi_board
create_hdl_core -file "$repo_root/hdl/qspi_board.vhd" -module {qspi_board} -library {work} -package {}
# Exporting BIF information of  HDL core command for module qspi_board
