#include "uart.h"

void kernel_main(void) {
    uart_init();

    uart_puts("\n\n");
    uart_puts("===========================================\n");
    uart_puts(" [OS Boot] Hello World from Oranges! \n");
    uart_puts(" Board: Orange Pi Zero 3 (Allwinner H618)  \n");
    uart_puts(" Arch : AArch64 (ARMv8-A Cortex-A53)       \n");
    uart_puts("===========================================\n\n");

    while (1) {
    }
}