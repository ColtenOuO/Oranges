.section ".text.boot"
.global _start

_start:
    /* 關閉所有 interrupt */
    msr daifset, #0xf

    /* 設定 Stack Pointer */
    ldr x0, =__stack_top
    mov sp, x0

    /* 清空 BSS */
    ldr x1, =__bss_start
    ldr x2, =__bss_end
1:
    cmp x1, x2
    b.ge 2f
    str xzr, [x1], #8
    b 1b

2:
    bl kernel_main

hang:
    wfe
    b hang