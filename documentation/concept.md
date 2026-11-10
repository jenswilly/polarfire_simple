# High-level Design of OpenCosmos ACU Software

This design assumes using a RTPFS160ZT-FCV784M PolarFire SoC containing 5 RISC-V cores and FPGA fabric.

## MSS

The MSS ("Microprocessor Subsystem") contains one E51 "supervisor" RISC-V core and 4 U54 "application" cores.

All interaction between the MSS and the FPGA is done using the AXI-based FIC_x interfaces. This means that using
memory mapped AXI/AXI-Lite control and DMA for AXI-Streaming.

### E51 Bootloader

The E51 core will run Microchip's HSS ("Hart Software Services") zero-stage bootloader and initialization 
software. This will, in turn, load the firmware for the four application cores from external QSPI Flash storage.

If at all possible, we should use Microchip's HSS instead of implementing our own zero-stage bootloader since
HSS is designed for low-level initialization and memory configuration of the SoC and has been extensively tested.

### U54 Application Cores

The application cores will run RTEMS (6.2) applications, reusing software developed for Univity as much as possible.

Tasks running here should be relatively slow without strict realtime requirements (still realtime, but not with
microsecond requirements). These tasks could include:

* CAN-based TC/TM parsing
* Telemetry reporting
* External ADC sampling
* External Watchdog updating
* Ethernet protocol handling
* Power supply control and monitoring
* State management for FPGA components
* LUT data updating
* Firmware updates
* Calculation pipeline: from spacecraft position/attitude plus target locations on Earth -> u/v components for eight beams

## FPGA

FPGA fabric will run five main components (and several "interface" and "sub-" components):

1. **System Control**  
   Controls high-level state and resets for other FPGA components. Controlled from MSS using AXI-Lite.
2. **Array Controller**  
   Reads u/v vector components from 8 "Beam FIFOs", each containing Steering Points (u/v, frequency) for each of the 8 beams.  
   Passes Steering Points to the individual Slice Controllers.  
   Also updates current temperature (from MSS via AXI) registers on Slice Controllers.  
   This is the top-level component wiring the subcomponents together.
3. **Calibration LUT Controller**  
   Loads calibration LUT data from MRAM (using MRAM Controller).  
   Data will be split and set on the individual Slice Controllers. That means that all calibration will be **pre-loaded** at
   startup and stored in RAM on the Slice Controllers (each getting full calibration data for their 10 BFICs).  
   Note that some kind of error detection/scrubbing will likely be needed since RAM is not SEU-safe.
4. **Slice Controller**  
   There will be 22 of these - each controlling one "slice" containing 10 BFICs.  
   One Slice Controller instance controls one SPI bus (and one set of GPIO lines).  
   The Slice Controller will handle all SPI and GPIO communication to the BFICs. Initialization/test is triggered by the System Control 
   component and when done/passed, the Slice Controller goes into Operational mode.  
   Calibration data is stored in RAM on each Slice Controller.  
   Tapering gains are hardcoded as generics on each Slice Controller.  
   Slice Controllers contain several subcomponents. In Operational mode, the controller reads u/v data (possibly already multiplied
   by X/Y element pitch) and frequency from Steering Point FIFOs, uses temperature and frequency to get calibration data from own
   RAM, formats the data correctly (adding BFIC and register headers) and adds the data to a block FIFO, from where the data is 
   serialized into single bytes and sent out in 10 byte blocks on the SPI bus.  
   The BSW signal is used to synchronize BFIC programming.
2. **MRAM Controller**  
   This HAL component is shared between several other components. One component at a tim has exclusive access
   based on the current state.
2. **LUT Updater**  
   Handles writes to external MRAM LUT. Controlled from MSS using AXI-Lite (for setup) and AXI-Streaming/DMA (for data).

### Issues

* **Timing, fan-out and propagation delay** for Slice Controller: nanosecond precision is required for the BSW signal.
* **SPI bus pad control**: strict timing/fan-out requirements for all SPI pads/IO buffer registers.
* **Validation of custom VHDL**
* **Repo/project organization** of shared components/interfaces from Univity project
* **Tooling setup:** both RTEMS/Cmake and FPGA tools, the latter of which require individual hardware-linked license files.
* **Hardware:** early access to boards with real components for SoC, MRAM, Ethernet PHY, QSPI Flash, watchdog, ADC is 
  required. This is not just a nice-to-have since micro- and nanosecond timing requirements are not possible to verify
  on prototype-only components and timing changes can require major redesign.
* **Security:** what kind of signing/encryption of SoC payloads do we need?

## Hardware Components

These are the components expected to be used:

* **RTPFS160ZT-FCV784M PolarFire SoC** - main SoC. 160k logic elements, radiation tolerant. The industrial version, **MPFS160T-FCVG784I** can be used for prototyping and _might_ also be used for the first EMs depending on availability of the rad. tolerant devices.
* **AS308G208 Space-Grade Dual-Quad Serial Persistent SRAM Memory** - LUT data storage. 1 GB capacity. Two QSPI flash dies. One will be used for the 
MSS to store firmware binaries and application data as well as storage area for firmware uploads.
* **SST26L064-80-RT/SM-HP Serial Flash Memory** - Radiation tolerant external QSPI-based flash storage for bitstream updates (same device as on Univity).