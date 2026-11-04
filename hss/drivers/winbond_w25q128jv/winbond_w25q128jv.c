/*
 * Winbond W25Q128JV (SPI NOR, 16 MB) driver for the HSS QSPI service.
 * See winbond_w25q128jv.h. Device facts: documentation/device_facts.md section 2
 * ([W] = W25Q128JV datasheet rev F, printed page numbers).
 *
 * All commands are 1-1-1 except the read, which is 6Bh (1-1-4) when SR2.QE = 1.
 * EBh (1-4-4) is not used: its mode byte M7-0 would have to come from the MSS QSPI
 * "idle" cycles, whose pin state isn't documented.
 *
 * Two clocks: commands, status, program and erase at W25Q128JV_CMD_CLK_DIV (5 MHz, sampled
 * on the rising SCLK edge, known to work), reads at W25Q128JV_READ_CLK_DIV (25 MHz). The
 * MSS QSPI reaches the pins through the fabric, so the read data's round trip (MSS ->
 * fabric -> pad -> flash tCLQV -> pad -> fabric -> MSS) is a large part of the 20 ns half
 * period at 25 MHz. Flash_init therefore calibrates: it reads CAL_LEN bytes from address 0
 * at the command clock as a reference, then at the read clock with each MSS QSPI sample
 * point, and uses the first that matches. If none matches, or the reference is uniform
 * (erased flash, nothing to compare), reads stay at the command clock. The HSS only
 * checks the boot image header CRC, not the data, so a bad fast read would otherwise go
 * unnoticed.
 *
 * Uses MSS_QSPI_polled_transfer_block(). It sends opcode + address + tx data as one
 * frame and accesses tx/rx buffers as 32-bit words, so both must be 4-byte aligned.
 * Every wait has a timeout (no flash fitted must not hang the HSS boot) and services
 * the E51 watchdog.
 */

#include "config.h"
#include "hss_types.h"
#include "hss_debug.h"
#include "hss_clock.h"

#include <string.h>

#include "encoding.h"           /* read_csr etc., needed by mss_plic.h via mss_qspi.h */
#include "winbond_w25q128jv.h"

#if IS_ENABLED(CONFIG_SERVICE_WDOG)
#  include "wdog_service.h"
#endif

/* Opcodes, [W] p.22-23 Table */
#define W25Q_WRITE_ENABLE       0x06u   /* [W] p.24 §8.2.1 */
#define W25Q_READ_SR1           0x05u   /* [W] p.25 §8.2.4 */
#define W25Q_READ_SR2           0x35u
#define W25Q_READ_JEDEC_ID      0x9Fu   /* [W] p.50 */
#define W25Q_ENABLE_RESET       0x66u   /* [W] p.59 §8.2.37 */
#define W25Q_RESET_DEVICE       0x99u
#define W25Q_PAGE_PROGRAM       0x02u   /* [W] p.36 §8.2.13 */
#define W25Q_BLOCK_ERASE_64K    0xD8u   /* [W] p.40 §8.2.17 */
#define W25Q_CHIP_ERASE         0xC7u   /* [W] p.41 §8.2.18 */
#define W25Q_FAST_READ          0x0Bu   /* 1-1-1, 8 dummy clocks */
#define W25Q_FAST_READ_QUAD_OUT 0x6Bu   /* 1-1-4, 8 dummy clocks, [W] p.31 §8.2.9 */

#define SR1_BUSY                0x01u   /* [W] p.13 Fig. 4a */
#define SR2_QE                  0x02u   /* [W] p.16 Fig. 4b */

#define READ_DUMMY_CLOCKS       8u

/* Timeouts: datasheet maximum plus margin ([W] p.65) */
#define TIMEOUT_PAGE_PROGRAM_MS 10u     /* tPP max 3 ms */
#define TIMEOUT_BLOCK_ERASE_MS  3000u   /* tBE2 max 2000 ms */
#define TIMEOUT_CHIP_ERASE_MS   250000u /* tCE max 200 s */

#define ADDR_BYTES              3u
#define CHUNK                   256u    /* Bounce buffer size, = page size */
#define CAL_LEN                 1024u   /* Calibration read length (from address 0) */

static mss_qspi_config_t g_qspi_config;
static bool g_read_quad = false;        /* 6Bh allowed (QE = 1) */
static bool g_first_init_done = false;

/* Read clock settings, from the calibration */
static mss_qspi_clk_div g_read_div = W25Q128JV_CMD_CLK_DIV;
static uint8_t g_read_sample = MSS_QSPI_SAMPLE_POSAGE_SPICLK;

static uint8_t g_cal_ref[CAL_LEN] __attribute__((aligned(4)));
static uint8_t g_cal_test[CAL_LEN] __attribute__((aligned(4)));

/* Frame buffer: opcode + 3 address bytes + one page */
static uint8_t g_frame[4u + W25Q128JV_PAGE_SIZE] __attribute__((aligned(4)));
static uint8_t g_rx[CHUNK] __attribute__((aligned(4)));

static void set_config_(mss_qspi_clk_div div, uint8_t sample, mss_qspi_io_format fmt)
{
    if ((g_qspi_config.clk_div != div) || (g_qspi_config.sample != sample)
        || (g_qspi_config.io_format != fmt)) {
        g_qspi_config.clk_div = div;
        g_qspi_config.sample = sample;
        g_qspi_config.io_format = fmt;
        MSS_QSPI_configure(&g_qspi_config);
    }
}

/* Back to the command settings, which everything except reads assumes */
static void set_cmd_config_(void)
{
    set_config_(W25Q128JV_CMD_CLK_DIV, MSS_QSPI_SAMPLE_POSAGE_SPICLK, MSS_QSPI_NORMAL);
}

static void command_(uint8_t opcode)
{
    g_frame[0] = opcode;
    MSS_QSPI_polled_transfer_block(0u, g_frame, 0u, NULL, 0u, 0u);
}

static uint8_t read_reg_(uint8_t opcode)
{
    g_frame[0] = opcode;
    MSS_QSPI_polled_transfer_block(0u, g_frame, 0u, g_rx, 1u, 0u);
    return g_rx[0];
}

static void set_addr_(uint8_t opcode, uint32_t addr)
{
    g_frame[0] = opcode;
    g_frame[1] = (uint8_t)(addr >> 16);
    g_frame[2] = (uint8_t)(addr >> 8);
    g_frame[3] = (uint8_t)addr;
}

/* Polls SR1.BUSY until clear. Returns 0 when ready, 1 on timeout. */
static uint8_t wait_ready_(uint32_t timeout_ms)
{
    const HSSTicks_t start = HSS_GetTime();

    while (read_reg_(W25Q_READ_SR1) & SR1_BUSY) {
#if IS_ENABLED(CONFIG_SERVICE_WDOG)
        HSS_Wdog_E51_Tickle();
#endif
        if (HSS_Timer_IsElapsed(start, (HSSTicks_t)timeout_ms * ONE_MILLISEC)) {
            return 1u;
        }
    }
    return 0u;
}

static uint32_t read_id_(void)
{
    g_frame[0] = W25Q_READ_JEDEC_ID;
    MSS_QSPI_polled_transfer_block(0u, g_frame, 0u, g_rx, 3u, 0u);
    return ((uint32_t)g_rx[0] << 16) | ((uint32_t)g_rx[1] << 8) | g_rx[2];
}

/* One read frame with the given clock settings; dst must be 4-byte aligned */
static void read_with_(void *dst, uint32_t addr, uint32_t len, bool quad,
    mss_qspi_clk_div div, uint8_t sample)
{
    set_config_(div, sample, quad ? MSS_QSPI_QUAD_EX_RO : MSS_QSPI_NORMAL);
    set_addr_(quad ? W25Q_FAST_READ_QUAD_OUT : W25Q_FAST_READ, addr);
    MSS_QSPI_polled_transfer_block(ADDR_BYTES, g_frame, 0u, dst, len, READ_DUMMY_CLOCKS);
    set_cmd_config_();
}

static void read_frame_(void *dst, uint32_t addr, uint32_t len)
{
    read_with_(dst, addr, len, g_read_quad, g_read_div, g_read_sample);
}

static unsigned sclk_mhz_(mss_qspi_clk_div div)
{
    /* Enum value n = divide by 2n; MSS AHB clock 150 MHz */
    return 150u / (2u * (unsigned)div);
}

static void calibrate_read_(void)
{
    static const struct {
        uint8_t sample;
        const char *name;
    } points[] = {
        { MSS_QSPI_SAMPLE_POSAGE_SPICLK, "posedge" },
        { MSS_QSPI_SAMPLE_ACTIVE_SPICLK, "active" },
        { MSS_QSPI_SAMPLE_NEGAGE_SPICLK, "negedge" },
    };

    /* Reference: 1-1-1 at the command clock */
    read_with_(g_cal_ref, 0u, CAL_LEN, false, W25Q128JV_CMD_CLK_DIV,
        MSS_QSPI_SAMPLE_POSAGE_SPICLK);

    bool uniform = true;
    for (uint32_t i = 1u; i < CAL_LEN; i++) {
        if (g_cal_ref[i] != g_cal_ref[0]) {
            uniform = false;
            break;
        }
    }
    if (uniform) {
        mHSS_DEBUG_PRINTF(LOG_NORMAL, "W25Q128JV: first %u bytes all %02x (erased?), "
            "no read calibration; reads at %u MHz\n", CAL_LEN, g_cal_ref[0],
            sclk_mhz_(W25Q128JV_CMD_CLK_DIV));
        return;
    }

    bool found = false;
    for (size_t p = 0u; p < ARRAY_SIZE(points); p++) {
        memset(g_cal_test, 0, CAL_LEN);
        read_with_(g_cal_test, 0u, CAL_LEN, g_read_quad, W25Q128JV_READ_CLK_DIV,
            points[p].sample);

        uint32_t bad = 0u;
        for (uint32_t i = 0u; i < CAL_LEN; i++) {
            if (g_cal_test[i] != g_cal_ref[i]) {
                bad++;
            }
        }
        mHSS_DEBUG_PRINTF(LOG_NORMAL, "W25Q128JV: %u MHz %s sample: %u/%u bytes differ\n",
            sclk_mhz_(W25Q128JV_READ_CLK_DIV), points[p].name, bad, CAL_LEN);

        if ((bad == 0u) && !found) {
            found = true;
            g_read_div = W25Q128JV_READ_CLK_DIV;
            g_read_sample = points[p].sample;
        }
    }

    if (!found) {
        mHSS_DEBUG_PRINTF(LOG_ERROR, "W25Q128JV: no sample point works at %u MHz; "
            "reads at %u MHz\n", sclk_mhz_(W25Q128JV_READ_CLK_DIV),
            sclk_mhz_(W25Q128JV_CMD_CLK_DIV));
    }
}

void Flash_init(mss_qspi_io_format io_format)
{
    (void)io_format;

    MSS_QSPI_init();
    g_qspi_config.clk_div   = W25Q128JV_CMD_CLK_DIV;
    g_qspi_config.sample    = MSS_QSPI_SAMPLE_POSAGE_SPICLK;
    g_qspi_config.spi_mode  = MSS_QSPI_MODE3;       /* Mode 0 and 3 supported, [W] p.11 §6.1 */
    g_qspi_config.xip       = MSS_QSPI_DISABLE;
    g_qspi_config.xip_addr  = 0u;
    g_qspi_config.io_format = MSS_QSPI_NORMAL;
    MSS_QSPI_configure(&g_qspi_config);

    if (g_first_init_done) {
        return;
    }
    g_first_init_done = true;

    const uint32_t id = read_id_();
    if (id != W25Q128JV_JEDEC_ID) {
        return;     /* No (or another) flash: qspi_api reports the ID and skips QSPI */
    }

    /* Software reset, only when no erase/program is running ([W] p.59). BUSY can still
     * be set after a warm reboot during an erase. */
    if (wait_ready_(TIMEOUT_BLOCK_ERASE_MS) == 0u) {
        command_(W25Q_ENABLE_RESET);
        command_(W25Q_RESET_DEVICE);
        HSS_SpinDelay_MilliSecs(1u);                /* tRST max 30 us, [W] p.65 */
    }

    const uint8_t sr1 = read_reg_(W25Q_READ_SR1);
    const uint8_t sr2 = read_reg_(W25Q_READ_SR2);
    g_read_quad = (W25Q128JV_READ_QUAD != 0) && ((sr2 & SR2_QE) != 0u);

    mHSS_DEBUG_PRINTF(LOG_NORMAL, "W25Q128JV: SR1 %02x SR2 %02x, reads %s\n",
        sr1, sr2, g_read_quad ? "1-1-4 (6Bh)" : "1-1-1 (0Bh)");

    calibrate_read_();

    mHSS_DEBUG_PRINTF(LOG_NORMAL, "W25Q128JV: reads at %u MHz, %s sample\n",
        sclk_mhz_(g_read_div),
        (g_read_sample == MSS_QSPI_SAMPLE_POSAGE_SPICLK) ? "posedge" :
        (g_read_sample == MSS_QSPI_SAMPLE_ACTIVE_SPICLK) ? "active" : "negedge");
}

void Flash_readid(uint8_t *buf)
{
    const uint32_t id = read_id_();
    buf[0] = (uint8_t)(id >> 16);
    buf[1] = (uint8_t)(id >> 8);
    buf[2] = (uint8_t)id;
}

void Flash_read(uint8_t *buf, uint32_t addr, uint32_t len)
{
    if (len == 0u) {
        return;
    }

    if (((uintptr_t)buf & 3u) == 0u) {
        read_frame_(buf, addr, len);
        return;
    }

    /* Unaligned destination: through the aligned bounce buffer */
    while (len) {
        const uint32_t n = (len > CHUNK) ? CHUNK : len;
        read_frame_(g_rx, addr, n);
        memcpy(buf, g_rx, n);
        buf += n;
        addr += n;
        len -= n;
    }
}

uint8_t Flash_program(uint8_t *buf, uint32_t addr, uint32_t len)
{
    while (len) {
        /* Up to the end of the current 256-byte page ([W] p.36: the address wraps
         * within the page) */
        uint32_t n = W25Q128JV_PAGE_SIZE - (addr % W25Q128JV_PAGE_SIZE);
        if (n > len) {
            n = len;
        }

        command_(W25Q_WRITE_ENABLE);
        set_addr_(W25Q_PAGE_PROGRAM, addr);
        memcpy(&g_frame[4], buf, n);
        MSS_QSPI_polled_transfer_block(ADDR_BYTES, g_frame, n, NULL, 0u, 0u);

        if (wait_ready_(TIMEOUT_PAGE_PROGRAM_MS)) {
            mHSS_DEBUG_PRINTF(LOG_ERROR, "W25Q128JV: program timeout at 0x%06x\n", addr);
            return 1u;
        }

        buf += n;
        addr += n;
        len -= n;
    }
    return 0u;
}

uint8_t Flash_sector_erase(uint32_t addr)
{
    command_(W25Q_WRITE_ENABLE);
    set_addr_(W25Q_BLOCK_ERASE_64K, addr & ~(W25Q128JV_BLOCK_SIZE - 1u));
    MSS_QSPI_polled_transfer_block(ADDR_BYTES, g_frame, 0u, NULL, 0u, 0u);

    if (wait_ready_(TIMEOUT_BLOCK_ERASE_MS)) {
        mHSS_DEBUG_PRINTF(LOG_ERROR, "W25Q128JV: erase timeout at 0x%06x\n", addr);
        return 1u;
    }
    return 0u;
}

uint8_t Flash_erase_block(uint16_t block_nb)
{
    if (block_nb >= W25Q128JV_BLOCK_COUNT) {
        return 1u;
    }
    return Flash_sector_erase((uint32_t)block_nb * W25Q128JV_BLOCK_SIZE);
}

uint8_t Flash_erase(void)
{
    command_(W25Q_WRITE_ENABLE);
    command_(W25Q_CHIP_ERASE);

    if (wait_ready_(TIMEOUT_CHIP_ERASE_MS)) {
        mHSS_DEBUG_PRINTF(LOG_ERROR, "W25Q128JV: chip erase timeout\n");
        return 1u;
    }
    return 0u;
}
