# Component user guides

One page per hand-written VHDL entity in `hdl/`: generics, ports, usage notes, sub-components and testbenches. Implementation details are in the source headers; the system view is in the top-level `README.md`.

All components use `clk` with a synchronous, active-low `reset_n` (except `axi_sys_ctrl`, which uses the AXI names `ACLK` / `ARESETN`). Testbenches run with `sim/run_tb.sh tb_<name>` and print `TB PASSED` / `TB FAILED`.

## General

| Component | Purpose |
|---|---|
| [axi_sys_ctrl](axi_sys_ctrl.md) | AXI4-Lite system control registers: LED bits, ID register, debug pulse. |
| [button_debounce](button_debounce.md) | Push-button debouncer with level output and press pulse. |
| [pulse_stretch](pulse_stretch.md) | Stretches a short pulse to a fixed length. |

## SPI TX path

| Component | Purpose |
|---|---|
| [spi_tx_path](spi_tx_path.md) | 80-bit blocks in, one SPI frame per block out. |
| [block_fifo](block_fifo.md) | Valid/ready wrapper around the 512-block CoreFIFO. |
| [block_serializer](block_serializer.md) | Block to AXI4-Stream bytes, MSB first. |
| [axis_spi_wo_master](axis_spi_wo_master.md) | Write-only AXI4-Stream SPI master. |
| [axis_spi_master](axis_spi_master.md) | Full-duplex AXI4-Stream SPI master (not used in TOP). |
| [block_arbiter](block_arbiter.md) | Round-robin arbiter for several block producers. |
| [test_block_producer](test_block_producer.md) | Test block source triggered by a pulse. |

## QSPI controller

| Component | Purpose |
|---|---|
| [qspi_board](qspi_board.md) | Controller + BIST with tristate pins (HDL+ core in TOP). |
| [qspi_bist](qspi_bist.md) | Self-test: write, calibrate, read and compare. |
| [qspi_mram_ctrl](qspi_mram_ctrl.md) | Controller top: init, read and write requests. |
| [qspi_init](qspi_init.md) | Memory reset, ID check and configuration. |
| [qspi_read_ctrl](qspi_read_ctrl.md) | Read requests to EBh commands with credit flow control. |
| [qspi_write](qspi_write.md) | Write requests to erase/program commands. |
| [qspi_xact](qspi_xact.md) | One command per CS# assertion. |
| [qspi_phy](qspi_phy.md) | Pin-level bit engine with RX sample delay. |

## Packages and models

Not components, but used by them:

| File | Purpose | Testbench |
|---|---|---|
| `hdl/util_pkg.vhd` | `clog2`, `reverse`, `ns_to_cycles`. | `tb_util_pkg` |
| `hdl/qspi_pkg.vhd` | QSPI types (`device_t`, `lane_mode_t`, `dir_t`, `cmd_lanes_t`), opcodes and device parameters. | `tb_qspi_pkg` |
| `sim/models/qspi_mem_model.vhd` | Simulation model of one W25Q128JV / AS308G208 die with protocol checks. | `tb_qspi_mem_model` |
