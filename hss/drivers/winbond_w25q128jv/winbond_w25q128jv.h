/*
 * Winbond W25Q128JV (SPI NOR, 16 MB) driver for the HSS QSPI service.
 *
 * Same Flash_* API as the HSS's micron_mt25q driver, so services/qspi/qspi_api.c and the
 * YMODEM loader can use it unchanged (apart from the driver selection, see
 * hss/patches/). Uses the MSS QSPI controller (routed through the fabric to the mikroBUS
 * Flash 6 Click in our design).
 *
 * Device facts (opcodes, timing) are from documentation/device_facts.md section 2.
 */

#ifndef WINBOND_W25Q128JV_H_
#define WINBOND_W25Q128JV_H_

#include <stdint.h>
#include "drivers/mss/mss_qspi/mss_qspi.h"

#ifdef __cplusplus
extern "C" {
#endif

#define W25Q128JV_JEDEC_ID      0xEF4018u   /* EFh Winbond, 40h type, 18h = 128 Mbit */
#define W25Q128JV_SIZE          (16u * 1024u * 1024u)
#define W25Q128JV_PAGE_SIZE     256u
#define W25Q128JV_BLOCK_SIZE    (64u * 1024u)
#define W25Q128JV_BLOCK_COUNT   (W25Q128JV_SIZE / W25Q128JV_BLOCK_SIZE)

/* SCLK = MSS AHB clock (150 MHz in our MSS) / divider.
 * Commands, status reads, program and erase: DIV_30 = 5 MHz (as the HSS's Micron driver;
 * their speed doesn't matter, YMODEM over the UART is far slower).
 * Reads: DIV_6 = 25 MHz, but only with a sample point that passed the calibration in
 * Flash_init (see winbond_w25q128jv.c); otherwise reads stay at the command clock. */
#ifndef W25Q128JV_CMD_CLK_DIV
#  define W25Q128JV_CMD_CLK_DIV  MSS_QSPI_CLK_DIV_30
#endif
#ifndef W25Q128JV_READ_CLK_DIV
#  define W25Q128JV_READ_CLK_DIV MSS_QSPI_CLK_DIV_6
#endif

/* 1: read with Fast Read Quad Output (6Bh, 1-1-4), 0: Fast Read (0Bh, 1-1-1).
 * Quad is used only if SR2.QE = 1 (factory-fixed on the -IQ parts). */
#ifndef W25Q128JV_READ_QUAD
#  define W25Q128JV_READ_QUAD   1
#endif

/* Configures the MSS QSPI controller. On the first call with a W25Q128JV present, also
 * resets the device (66h/99h), checks SR2.QE and calibrates the fast read. io_format is
 * ignored: reads always use the mode selected by W25Q128JV_READ_QUAD, everything else
 * is 1-1-1. */
void Flash_init(mss_qspi_io_format io_format);

/* Reads the 3-byte JEDEC ID (9Fh) into buf[0..2]. */
void Flash_readid(uint8_t *buf);

/* Reads len bytes from flash address addr. */
void Flash_read(uint8_t *buf, uint32_t addr, uint32_t len);

/* Programs len bytes at addr (split at 256-byte page boundaries). The area must be
 * erased. Returns 0 on success, non-zero on a timeout. */
uint8_t Flash_program(uint8_t *buf, uint32_t addr, uint32_t len);

/* Erases the 64 KB block that contains addr (D8h). Returns 0 on success. */
uint8_t Flash_sector_erase(uint32_t addr);

/* Erases 64 KB block number block_nb (D8h). Returns 0 on success. */
uint8_t Flash_erase_block(uint16_t block_nb);

/* Erases the whole device (C7h, up to 200 s). Returns 0 on success. */
uint8_t Flash_erase(void);

#ifdef __cplusplus
}
#endif

#endif /* WINBOND_W25Q128JV_H_ */
