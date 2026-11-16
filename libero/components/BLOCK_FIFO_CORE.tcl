# Exporting Component Description of BLOCK_FIFO_CORE to TCL
# Family: PolarFireSoC
# Part Number: MPFS095T-1FCSG325E
# Create and Configure the core component BLOCK_FIFO_CORE
create_and_configure_core -core_vlnv {Actel:DirectCore:COREFIFO:4.0.139} -component_name {BLOCK_FIFO_CORE} -params {\
"AE_DYN_EN:false"  \
"AE_STATIC_EN:false"  \
"AEVAL:4"  \
"AF_DYN_EN:false"  \
"AF_STATIC_EN:false"  \
"AFVAL:1020"  \
"CTRL_TYPE:2"  \
"ECC:0"  \
"ESTOP:true"  \
"FSTOP:true"  \
"FWFT:true"  \
"LEGACY:1"  \
"NUM_STAGES:2"  \
"OVERFLOW_EN:false"  \
"PIPE:1"  \
"PREFETCH:false"  \
"RAM_OPT:0"  \
"RDCNT_EN:false"  \
"RDEPTH:64"  \
"RE_POLARITY:0"  \
"READ_DVALID:false"  \
"RWIDTH:80"  \
"SYNC:1"  \
"SYNC_RESET:1"  \
"UNDERFLOW_EN:false"  \
"WDEPTH:64"  \
"WE_POLARITY:0"  \
"WRCNT_EN:false"  \
"WRITE_ACK:false"  \
"WWIDTH:80"   }
# Exporting Component Description of BLOCK_FIFO_CORE to TCL done
