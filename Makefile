BASENAME  = chameleontwist
VERSION  := jp

# Directories

BUILD_DIR = build
ASM_DIRS  = asm
BIN_DIRS  = assets
SRC_DIR   = src.$(VERSION)

SRC_DIRS  = $(SRC_DIR)

TOOLS_DIR = tools

# Files

S_FILES         = $(foreach dir,$(ASM_DIRS),$(wildcard $(dir)/*.s))
C_FILES         = $(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.c))
# H_FILES       = $(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.h))
BIN_FILES       = $(foreach dir,$(BIN_DIRS),$(wildcard $(dir)/*.bin))

O_FILES := $(foreach file,$(S_FILES),$(BUILD_DIR)/$(file).o) \
           $(foreach file,$(C_FILES),$(BUILD_DIR)/$(file).o) \
           $(foreach file,$(BIN_FILES),$(BUILD_DIR)/$(file).o)



# function is not included unless explicitly undefined
UNDEFINED_SYMS  := osViGetCurrentLine

# Tools

CROSS    = mips-linux-gnu-

AS       = $(CROSS)as
CPP      = cpp
LD       = $(CROSS)ld
OBJDUMP  = $(CROSS)objdump
OBJCOPY  = $(CROSS)objcopy
PYTHON   = python3
GCC      = gcc

XGCC     = mips-linux-gnu-gcc

GREP     = grep -rl
CC       = $(TOOLS_DIR)/ido5.3_recomp/cc
SPLAT    = $(TOOLS_DIR)/splat/split.py

# Flags

OPT_FLAGS      = -O2
LOOP_UNROLL    =

MIPSISET       = -mips2 -32

INCLUDE_CFLAGS = -I . -I include -I include/2.0 -I include/2.0/PR -I include/libc -I assets \
                 -I src.$(VERSION)

ASFLAGS        = -EB -mtune=vr4300 -march=vr4300 -mabi=32 -I include
OBJCOPYFLAGS   = -O binary

# Files requiring pre/post-processing
GLOBAL_ASM_C_FILES := $(shell $(GREP) GLOBAL_ASM $(SRC_DIR) </dev/null 2>/dev/null)
GLOBAL_ASM_O_FILES := $(foreach file,$(GLOBAL_ASM_C_FILES),$(BUILD_DIR)/$(file).o)


DEFINES := -D_LANGUAGE_C -D_FINALROM -DF3DEX_GBI -DWIN32 -DSSSV -DNDEBUG

ifeq ($(VERSION),us)
DEFINES += -DVERSION_US
endif
ifeq ($(VERSION),eu)
DEFINES += -DVERSION_EU
endif

VERIFY = verify

ifeq ($(NON_MATCHING),1)
DEFINES += -DNON_MATCHING
VERIFY = no_verify
PROGRESS_NONMATCHING = --non-matching
endif

CFLAGS := -G 0 -Xfullwarn -Xcpluscomm -signed -nostdinc -non_shared -Wab,-r4300_mul
CFLAGS += $(DEFINES)
# ignore compiler warnings about anonymous structs
CFLAGS += -woff 649,838
CFLAGS += $(INCLUDE_CFLAGS)

CHECK_WARNINGS := -Wall -Wextra -Wno-format-security -Wno-unknown-pragmas -Wno-unused-parameter -Wno-unused-variable -Wno-missing-braces -Wno-int-conversion
CC_CHECK := $(GCC) -fsyntax-only -fno-builtin -fsigned-char -std=gnu90 -m32 $(CHECK_WARNINGS) $(INCLUDE_CFLAGS) $(DEFINES)

GCC_FLAGS := $(INCLUDE_CFLAGS) $(DEFINES)
GCC_FLAGS += -G 0 -mno-shared -march=vr4300 -mfix4300 -mabi=32 -mhard-float
GCC_FLAGS += -mdivide-breaks -fno-stack-protector -fno-common -fno-zero-initialized-in-bss -fno-PIC -mno-abicalls -fno-strict-aliasing -fno-inline-functions -ffreestanding -fwrapv
GCC_FLAGS += -Wall -Wextra -Wno-missing-braces

TARGET     = $(BUILD_DIR)/$(BASENAME).$(VERSION)
LD_SCRIPT  = $(BASENAME).ld

LD_FLAGS   = -T $(LD_SCRIPT) -T undefined_syms_auto.txt -T undefined_funcs_auto.txt
LD_FLAGS  += -Map $(TARGET).map --no-check-sections

LD_FLAGS_EXTRA += $(foreach sym,$(UNDEFINED_SYMS),-u $(sym))

ASM_PROCESSOR_DIR := $(TOOLS_DIR)/asm-processor

### Targets

default: all

all: dirs $(VERIFY)

dirs:
	$(foreach dir,$(SRC_DIRS) $(ASM_DIRS) $(BIN_DIRS),$(shell mkdir -p $(BUILD_DIR)/$(dir)))

check: .baserom.$(VERSION).ok

verify: $(TARGET).z64
	@echo "$$(cat $(BASENAME).$(VERSION).sha1)  $(TARGET).z64" | sha1sum --check

no_verify: $(TARGET).z64
	@echo "Skipping SHA1SUM check!"

progress: dirs $(VERIFY) progress.csv

splat: $(SPLAT)

extract: splat tools
	$(PYTHON) $(SPLAT) $(BASENAME).$(VERSION).yaml


clean:
	rm -rf asm
	rm -rf assets
	rm -rf build
	rm -f *auto.txt


### Recipes

.baserom.$(VERSION).ok: baserom.$(VERSION).z64
	@echo "$$(cat $(BASENAME).$(VERSION).sha1)  $<" | sha1sum --check
	@touch $@

$(TARGET).elf: $(BASENAME).ld $(BUILD_DIR)/ $(O_FILES)
	$(LD) $(LD_FLAGS) $(LD_FLAGS_EXTRA) -o $@

ifndef PERMUTER
$(GLOBAL_ASM_O_FILES): $(BUILD_DIR)/%.c.o: %.c include/functions.$(VERSION).h include/variables.$(VERSION).h include/structs.h
	$(CC_CHECK) $<
	$(PYTHON) $(ASM_PROCESSOR_DIR)/asm_processor.py $(OPT_FLAGS) $< > $(BUILD_DIR)/$<
	$(CC) -c -32 $(CFLAGS) $(OPT_FLAGS) $(LOOP_UNROLL) $(MIPSISET) -o $@ $(BUILD_DIR)/$<
	$(PYTHON) $(ASM_PROCESSOR_DIR)/asm_processor.py $(OPT_FLAGS) $< --post-process $@ \
		--assembler "$(AS) $(ASFLAGS)" --asm-prelude $(ASM_PROCESSOR_DIR)/prelude.s
endif

# non asm-processor recipe
$(BUILD_DIR)/%.c.o: %.c
	$(CC_CHECK) $<
	$(CC) -c $(CFLAGS) $(OPT_FLAGS) $(LOOP_UNROLL) $(MIPSISET) -o $@ $<

# use modern gcc for data
$(BUILD_DIR)/$(SRC_DIR)/data/%.c.o: $(SRC_DIR)/data/%.c
	$(XGCC) -c $(GCC_FLAGS) -o $@ $<

$(BUILD_DIR)/%.s.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/%.bin.o: %.bin
	$(LD) -r -b binary -o $@ $<

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) $(OBJCOPYFLAGS) $< $@

$(TARGET).z64: $(TARGET).bin
	@cp $< $@

# progress
progress.csv: progress.main.csv progress.lib.csv progress.overlay1.csv progress.overlay2.csv
	cat $^ > $@

progress.main.csv: $(TARGET).elf
	$(PYTHON) $(TOOLS_DIR)/progress.py . $(TARGET).map .main --version $(VERSION) $(PROGRESS_NONMATCHING) > $@
progress.lib.csv: $(TARGET).elf
	$(PYTHON) $(TOOLS_DIR)/progress.py . $(TARGET).map .main_lib --version $(VERSION) $(PROGRESS_NONMATCHING) > $@
progress.overlay1.csv: $(TARGET).elf
	$(PYTHON) $(TOOLS_DIR)/progress.py . $(TARGET).map .overlay1 --version $(VERSION) $(PROGRESS_NONMATCHING) > $@
progress.overlay2.csv: $(TARGET).elf
	$(PYTHON) $(TOOLS_DIR)/progress.py . $(TARGET).map .overlay2 --version $(VERSION) $(PROGRESS_NONMATCHING) > $@

# fake targets for better error handling
$(SPLAT):
	$(info Repo cloned without submodules, attempting to fetch them now...)
	@which git >/dev/null || echo "ERROR: git binary not found on PATH"
	@which git >/dev/null
	git submodule update --init --recursive

baserom.$(VERSION).z64:
	$(error Place the JP chameleon twist ROM, named '$@', in the root of this repo and try again.)

### Settings
.SECONDARY:
.PHONY: all clean default
SHELL = /bin/bash -e -o pipefail