/*
 * polarfire_simple LED test - runs on E51 (hart 0)
 *   0x6000_0000 : LED register (bit0 = LED2, bit1 = LED3)
 *   0x6000_0004 : ID register (expect 0x1ED50001)
 *   0x6000_0008 : DEBUG (write-only): writing 1 gives a 1 ms pulse on the DEBUG pin
 *                 and sends one test block over SPI (not used here yet)
 */
#include "drivers/mss/mss_mmuart/mss_uart.h"
#include "mpfs_hal/mss_hal.h"
#include <stdio.h>

#define LED_REG_BASE 0x60000000UL
#define LED_REG (*(volatile uint32_t *)(LED_REG_BASE + 0x0U))
#define LED_ID_REG (*(volatile uint32_t *)(LED_REG_BASE + 0x4U))

volatile uint32_t count_sw_ints_h0 = 0U;

static void uart_print(const char *s) {
  MSS_UART_polled_tx_string(&g_mss_uart0_lo, (const uint8_t *)s);
}

/* Busy-wait using the CLINT mtime counter (LIBERO_SETTING_MSS_RTC_TOGGLE_CLK = 1 MHz) */
static void delay_ms(uint32_t ms)
{
    const uint64_t ticks = (uint64_t)ms * (LIBERO_SETTING_MSS_RTC_TOGGLE_CLK / 1000U);
    const uint64_t start = readmtime();

    while ((readmtime() - start) < ticks)
    {
    }
}

void e51(void) {
  char buf[80];
  uint32_t count = 0U;

  /* MMUART0 is routed through the fabric to the FTDI (pins Y21/W21) */
  (void)mss_config_clk_rst(MSS_PERIPH_MMUART0, (uint8_t)MPFS_HAL_FIRST_HART,
                           PERIPHERAL_ON);
  /* FIC0: MSS -> fabric AXI path to axi_led_reg */
  (void)mss_config_clk_rst(MSS_PERIPH_FIC0, (uint8_t)MPFS_HAL_FIRST_HART,
                           PERIPHERAL_ON);

  MSS_UART_init(&g_mss_uart0_lo, MSS_UART_115200_BAUD,
                MSS_UART_DATA_8_BITS | MSS_UART_NO_PARITY |
                    MSS_UART_ONE_STOP_BIT);

  uart_print("\r\n\r\n*** polarfire_simple LED test (E51) ***\r\n");
  snprintf(buf, sizeof(buf), "ID register: 0x%08lX (expect 0x1ED50001)\r\n",
           (unsigned long)LED_ID_REG);
  uart_print(buf);

  while (1U) {
    delay_ms(500U);

    count = (count + 1U) & 0x3U;
    LED_REG = count;

    snprintf(buf, sizeof(buf), "LED <- %lu, readback %lu\r\n",
             (unsigned long)count, (unsigned long)(LED_REG & 0x3U));
    uart_print(buf);
  }
}

void Software_h0_IRQHandler(void) { count_sw_ints_h0++; }
