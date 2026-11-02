# High-level Design of OpenCosmos ACU Software

This design assumes using a MPFS160T-FCVG784I PolarFire SoC containing 5 RISC-V cores and FPGA fabric.

## MSS

The MSS ("Microprocessor Subsystem") contains one E51 "supervisor" RISC-V core and 4 U54 "application" cores.

All interaction between the MSS and the FPGA is done using the AXI-based FIC_x interfaces. This means that using
memory mapped AXI/AXI Lite control and DMA for AXI Streaming.

### E51 Bootloader

The E51 cores will run Microchip's HSS ("Hart Software Services") stage zero bootloader and initialization 
software. This will in turn load the firmware for the four application cores from external QSPI Flash storage.

### U54 Application Cores

The application cores will run RTEMS (6.2) applications, reusing software developed for Univity as much as possible.

Tasks running here should be relatively slow without strict realtime requirements. These tasks could include:

* CAN-based TC/TM parsing
* External ADC sampling
* External Watchdog updating
* Ethernet protocol handling
* Power supply control and monitoring



