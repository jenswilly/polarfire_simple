set_component BLOCK_FIFO_CORE_BLOCK_FIFO_CORE_0_COREFIFO
set_false_path  -to [ get_cells { genblk*.U_corefifo_async/*/*shift_reg* } ]