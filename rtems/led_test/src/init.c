/*
 * polarfire_simple LED test - RTEMS 6.2 on U54_1, started by the HSS.
 * Same function as the bare-metal softconsole/led_test (E51):
 *   0x6000_0000 : LED register (bit0 = LED2, bit1 = LED3)
 *   0x6000_0004 : ID register (expect 0x1ED50001)
 *   0x6000_0008 : DEBUG (write-only), not used here
 *
 * The HSS has already enabled the MMUART0 and FIC0 clocks, released their
 * resets and released the fabric reset. The console is MMUART0 (device tree
 * rtems/dts/mpfs-discovery-kit.dts).
 */
#include <rtems.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

#define LED_REG_BASE 0x60000000UL
#define LED_REG (*(volatile uint32_t *)(LED_REG_BASE + 0x0U))
#define LED_ID_REG (*(volatile uint32_t *)(LED_REG_BASE + 0x4U))

static rtems_task Init(rtems_task_argument argument) {
  uint32_t count = 0U;

  (void)argument;

  printf("\n\n*** polarfire_simple LED test (RTEMS, U54_1) ***\n");
  printf("ID register: 0x%08" PRIX32 " (expect 0x1ED50001)\n", LED_ID_REG);

  while (1) {
    (void)rtems_task_wake_after(RTEMS_MILLISECONDS_TO_TICKS(500));

    count = (count + 1U) & 0x3U;
    LED_REG = count;

    printf("LED <- %" PRIu32 ", readback %" PRIu32 "\n", count,
           LED_REG & 0x3U);
  }
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER

#define CONFIGURE_MAXIMUM_TASKS 1
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE

#define CONFIGURE_INIT
#include <rtems/confdefs.h>
