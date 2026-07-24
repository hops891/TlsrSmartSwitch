
PROJECT_NAME ?= switch44
VERSION_BIN ?=

TEL_CHIP := $(POJECT_DEF) -DMCU_CORE_8258=1 -DROUTER=1 -DMCU_STARTUP_8258=1

#All libs: -ldrivers_826x -ldrivers_8258 -ldrivers_8278 -lsoft-fp -lfirmware_encrypt -lzb_coordinator -lzb_ed -lzb_router

PGM_PORT?=COM5
PGM_PORT_BAUD?=1500000 

PROJECT_PATH ?= .
SRC_DIR ?= /src
SRC_PATH ?= $(PROJECT_PATH)$(SRC_DIR)
# TEL_PATH:  Telink SDK - tc32/bin/
TEL_PATH ?= .
# SDK_PATH: X:/Telink/tl_zigbee_sdk

SDK_z_PATH ?= ./SDK_z/tl_zigbee_sdk

USE_ZB ?=0

OUT_PATH ?=./build
BIN_PATH ?=./bin

PYTHON ?= python

OBJ_SRCS :=
S_SRCS :=
ASM_SRCS :=
C_SRCS :=
S_UPPER_SRCS :=
O_SRCS :=
FLASH_IMAGE :=
ELFS :=
OBJS :=
LST :=
SIZEDUMMY :=
OUT_DIR :=

COMPILEOS = $(shell uname -o)
LINUX_OS = GNU/Linux


CUR_OS := linux
TOOLS_PATH := $(TEL_PATH)/tools/linux

TC32_PATH := $(TOOLS_PATH)/tc32/bin/

LNK_FLAGS := --gc-sections -nostartfiles

GCC_FLAGS := \
-O2 \
-ffunction-sections \
-fdata-sections \
-Wall \
-fpack-struct \
-fshort-enums \
-finline-small-functions \
-std=gnu99 \
-funsigned-char \
-fshort-wchar \
-fms-extensions \
-nostartfiles \
-nostdlib

ASM_FLAGS := \
-fomit-frame-pointer \
-fshort-enums \
-Wall \
-Wpacked \
-Wcast-align \
-fdata-sections \
-ffunction-sections \
-fno-use-cxa-atexit \
-fno-rtti \
-fno-threadsafe-statics



# MAKE_PATH: project all make

MAKE_PATH ?= ./make_z

SDK_PATH ?= $(SDK_z_PATH)

SDK_FLAGS := $(SDK_PATH)/zigbee

LS_FLAGS := $(SRC_PATH)/boot_z.link

LIBS := -lsoft-fp -ldrivers_8258 -lzb_router

INCLUDE_PATHS := -I$(SRC_PATH) -I$(SRC_PATH)/patch_z_sdk  -I$(SRC_PATH)/custom_zcl\
-I$(SDK_PATH)/platform \
-I$(SDK_PATH)/platform/chip_8258 \
-I$(SDK_PATH)/proj  \
-I$(SDK_PATH)/proj/common \
-I$(SDK_PATH)/zigbee/af \
-I$(SDK_PATH)/zigbee/include \
-I$(SDK_PATH)/zigbee/bdb/includes \
-I$(SDK_PATH)/zigbee/common/includes \
-I$(SDK_PATH)/zigbee/ota \
-I$(SDK_PATH)/zigbee/zbapi \
-I$(SDK_PATH)/zigbee/zbhci \
-I$(SDK_PATH)/zigbee/zcl \
-I$(SDK_PATH)/zigbee/gp \
-I$(SDK_PATH)/zigbee/zdo




GCC_FLAGS += $(TEL_CHIP)

LS_INCLUDE := -L$(SDK_PATH)/platform/lib -L$(SDK_PATH)/platform/tc32 -L$(SDK_PATH)/zigbee/lib/tc32 -L$(SDK_PATH)/proj -L$(SDK_PATH)/platform -L$(OUT_PATH)

#include Project makefile
-include $(MAKE_PATH)/src.mk
#include SDK makefile
-include $(MAKE_PATH)/platform.mk
-include $(MAKE_PATH)/proj.mk
-include $(MAKE_PATH)/zigbee.mk
-include $(MAKE_PATH)/gp.mk
-include $(MAKE_PATH)/zbhci.mk

-include $(MAKE_PATH)/zdo.mk
-include $(MAKE_PATH)/zcl.mk
-include $(MAKE_PATH)/wwah.mk
-include $(MAKE_PATH)/ss.mk
-include $(MAKE_PATH)/ota.mk
-include $(MAKE_PATH)/mac.mk

-include $(MAKE_PATH)/common.mk
-include $(MAKE_PATH)/bdb.mk
-include $(MAKE_PATH)/aps.mk
-include $(MAKE_PATH)/af.mk
-include $(MAKE_PATH)/zbhci.mk
-include $(MAKE_PATH)/div_mod.mk
-include ./project.mk

# Add inputs and outputs from these tool invocations to the build variables
LST_FILE := $(OUT_PATH)/$(PROJECT_NAME).lst
BIN_FILE := $(BIN_PATH)/$(PROJECT_NAME)$(VERSION_BIN).bin
OTA_FILE := $(BIN_PATH)/$(PROJECT_NAME).zigbee
ELF_FILE := $(OUT_PATH)/$(PROJECT_NAME).elf

SIZEDUMMY := sizedummy

# All Target
all: pre-build main-build

# Main-build Target
main-build: $(ELF_FILE) secondary-outputs

OBJ_LIST := $(OBJS) $(USER_OBJS)
# Tool invocations
$(ELF_FILE): $(OBJ_LIST)
	@echo 'Building Standard target: $@'

	@$(TC32_PATH)tc32-elf-ld --gc-sections -L $(SDK_PATH)/zigbee/lib/tc32 -L $(SDK_PATH)/platform/lib -L $(SDK_PATH)/platform/tc32 -T $(LS_FLAGS) -o "$(ELF_FILE)" $(OBJS) $(USER_OBJS) $(LIBS)
	@echo 'Finished building target: $@'
	@echo ' '

$(LST_FILE): $(ELF_FILE)
	@echo 'Invoking: TC32 Create Extended Listing'
	@$(TC32_PATH)tc32-elf-objdump -x -D -l -S  $(ELF_FILE)  > $(LST_FILE)
	@echo 'Finished building: $@'
	@echo ' '

$(BIN_FILE): $(ELF_FILE)
	@echo 'Create Flash image (binary format)'
	@echo ' '
	@$(TC32_PATH)tc32-elf-objcopy -v -O binary $(ELF_FILE) $(BIN_FILE)
	@echo ' '
	@$(PYTHON) $(MAKE_PATH)/tl_check_fw.py $(BIN_FILE)
	@echo 'Finished building: $@'
	@echo ' '

$(OTA_FILE): $(BIN_FILE)
	@echo 'Create OTA image'
	@echo ' '
	@$(PYTHON) $(MAKE_PATH)/zigbee_ota.py $(BIN_FILE) -p $(BIN_PATH) -n $(PROJECT_NAME) -s "Telink-pvvx:$(PROJECT_NAME)_z"
	@echo ' '

sizedummy: $(ELF_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrMemInfo.py -t $(TC32_PATH)tc32-elf-nm $(ELF_FILE)
	@echo ' '

clean:
	@$(RM) $(FLASH_IMAGE) $(ELFS) $(OBJS) $(LST) $(SIZEDUMMY) $(ELF_FILE) $(BIN_FILE) $(LST_FILE)
	@echo 'Clean ...'
	@echo ' '

pre-build:
ifneq ($(SDK_FLAGS), $(wildcard $(SDK_FLAGS)))
	$(error "Please check SDK_Path")
endif
	@mkdir -p $(foreach s,$(OUT_DIR),$(OUT_PATH)$(s))
	@mkdir -p $(BIN_PATH)
	@echo ' '

secondary-outputs: $(BIN_FILE) $(OTA_FILE) $(LST_FILE) $(SIZEDUMMY)


flash: $(BIN_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 -a-50 -s we 0 $(BIN_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -m i

# test start from OTA BLE
flash_ble: $(BIN_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 -a-50 -s i
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) es 0 1
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) we 0x20000 $(BIN_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -m i

# test start from Tuya boot_loader
flash_tuya: $(BIN_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 -a-50 -s i
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) we 0 tuya_boot.bin
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) we 0x8000 $(BIN_FILE)
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -m i	

reset:
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 -m -w i

erase:
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 -s ea

info:
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 i

stop:
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -z15 -s i

go:
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -b$(PGM_PORT_BAUD) -m

TADDR?=0x008423a0
TLEN?=128
test_damp:
	@$(PYTHON) $(MAKE_PATH)/TlsrPgm.py -p$(PGM_PORT) -z10 -c -g ds $(TADDR) $(TLEN)

install: $(SDK_FLAGS) $(TC32_PATH)
	@echo "SDK & TC32 installed."
	@echo "Use: make clean"
	@echo "     make all"

$(SDK_FLAGS): $(SDK_PATH)
ifneq ($(SDK_FLAGS),$(wildcard $(SDK_FLAGS)))
	@unzip -o $(TEL_PATH)/tools/SDK_z.zip -d $(SDK_z_PATH)
endif

$(SDK_PATH):
	mkdir -p $(SDK_PATH)

$(TC32_PATH): $(TOOLS_PATH)
ifneq ($(TC32_PATH),$(wildcard $(TC32_PATH)))
	@tar -xvjf $(TOOLS_PATH)/tc32_gcc_v2.0.tar.bz2 -C $(TOOLS_PATH)
endif

$(TOOLS_PATH):
	mkdir -p $(TOOLS_PATH)


.PHONY: all clean
.SECONDARY: main-build
