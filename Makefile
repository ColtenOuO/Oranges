CROSS_COMPILE ?= $(shell which aarch64-none-elf-gcc >/dev/null 2>&1 && echo aarch64-none-elf- || echo aarch64-linux-gnu-)

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

CFLAGS = -Wall -O2 -ffreestanding -nostdlib -nostartfiles -mcpu=cortex-a53 \
         -Isrc/drivers -MMD -MP

BUILD = build
OBJDIR = $(BUILD)/kernel
SRCS = src/arch/aarch64/boot.S \
       src/kernel/main.c \
       src/drivers/uart.c
OBJS = $(patsubst src/%,$(OBJDIR)/%.o,$(SRCS))

all: $(BUILD)/kernel.bin

$(BUILD)/kernel.bin: $(BUILD)/kernel.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/kernel.elf: $(OBJS) linker.ld
	$(LD) -T linker.ld $(OBJS) -o $@

$(OBJDIR)/%.o: src/%
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(OBJDIR) $(BUILD)/kernel.elf $(BUILD)/kernel.bin

-include $(OBJS:.o=.d)

.PHONY: all clean
