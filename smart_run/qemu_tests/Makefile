# qemu_tests/Makefile — RVV firmware tests via qemu-riscv64
# Toolchain : riscv64-unknown-elf-gcc (rv64imafdcv)
# Runtime   : qemu-riscv64 Linux user-mode

CC      := riscv64-unknown-elf-gcc
OBJDUMP := riscv64-unknown-elf-objdump
QEMU    := qemu-riscv64

MARCH   := rv64imafdcv
MABI    := lp64d

CFLAGS  := -march=$(MARCH) -mabi=$(MABI) -mtune=thead-c906 \
            -O2 -g \
            -nostdlib -static \
            -fno-builtin \
            -I src \
            -Wall -Wno-incompatible-pointer-types

LDFLAGS := -nostdlib -static

SRCDIR  := src
SYSDIR  := src/sys
BINDIR  := build

SYS_SRCS := $(wildcard $(SYSDIR)/*.c)
SYS_OBJS := $(patsubst $(SYSDIR)/%.c, $(BINDIR)/sys/%.o, $(SYS_SRCS))

APP_SRCS := $(wildcard $(SRCDIR)/*.c)
APP_BINS := $(patsubst $(SRCDIR)/%.c, $(BINDIR)/%, $(APP_SRCS))

.PHONY: all run clean help

all: $(APP_BINS)

$(BINDIR)/%: $(SRCDIR)/%.c $(SYS_OBJS) | $(BINDIR)
	$(CC) $(CFLAGS) $< $(SYS_OBJS) -o $@ $(LDFLAGS) -lgcc

$(BINDIR)/sys/%.o: $(SYSDIR)/%.c | $(BINDIR)/sys
	$(CC) $(CFLAGS) -c $< -o $@

$(BINDIR):
	mkdir -p $(BINDIR)

$(BINDIR)/sys:
	mkdir -p $(BINDIR)/sys

run: all
	@for bin in $(APP_BINS); do \
		echo "========================================"; \
		echo "Running: $$bin  [$(MARCH)/$(MABI)]"; \
		echo "========================================"; \
		$(QEMU) $$bin; \
		echo "Exit: $$?"; \
		echo ""; \
	done

run-%: $(BINDIR)/%
	$(QEMU) $<

disasm-%: $(BINDIR)/%
	$(OBJDUMP) -d --no-show-raw-insn $< | less

clean:
	rm -rf $(BINDIR)

help:
	@echo "Targets:"
	@echo "  make              Build all test binaries"
	@echo "  make run          Build and run all via qemu-riscv64"
	@echo "  make run-NAME     Build and run src/NAME.c"
	@echo "  make disasm-NAME  Disassemble build/NAME"
	@echo "  make clean        Remove build/"
	@echo ""
	@echo "  Toolchain : $(CC)"
	@echo "  March     : $(MARCH)  ABI: $(MABI)"
	@echo "  QEMU      : $(QEMU)"
