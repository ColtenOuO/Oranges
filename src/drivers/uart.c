#include "uart.h"

#define UART0_BASE 0x05000000
#define UART0_THR  (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_LSR  (*(volatile uint32_t *)(UART0_BASE + 0x14))

#define LSR_THRE   (1 << 5)

void uart_init(void) {

}

void uart_putc(char c) {
    while ((UART0_LSR & LSR_THRE) == 0);
    UART0_THR = (uint32_t)c;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}