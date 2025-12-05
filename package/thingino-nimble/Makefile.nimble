#
# Thingino NimBLE Library - Build libnimble.so
#
# This Makefile builds a shared library (libnimble.so) from the NimBLE stack
# in the atbm-wifi project, suitable for use with libblepp and other BLE clients.
#
# Based on atbm-thingino-ble Makefile approach
#

# Toolchain commands (will be overridden by buildroot)
CROSS_COMPILE ?= mips-linux-gnu-
CC      := $(CROSS_COMPILE)gcc
LD      := $(CROSS_COMPILE)gcc
AR      := $(CROSS_COMPILE)ar
SIZE    := $(CROSS_COMPILE)size

# Configuration - use APP mode to get correct includes, but build as library
CONFIG_LINUX_BLE_STACK_APP = y
CONFIG_LINUX_BLE_STACK_LIB = n

# Directory paths (relative to where make is run - the build directory)
BLE_HOST_ROOT := ble_host
NIMBLE_ROOT   := $(BLE_HOST_ROOT)/nimble_v42
OS_DIR        := os

# Musl-compatible OS layer sources (copied from atbm-thingino-ble approach)
OS_SRC := \
	$(OS_DIR)/os_atomic.c \
	$(OS_DIR)/os_mutex.c \
	$(OS_DIR)/os_eventq.c \
	$(OS_DIR)/os_task.c \
	$(OS_DIR)/os_stubs.c

# Include other OS layer sources from ble_host
OS_SRC += \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_callout.c \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_sem.c \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_time.c

# Include NimBLE host components
include $(NIMBLE_ROOT)/Makefile_host.include

# Skip files that don't build for this port
NIMBLE_IGNORE := \
	$(NIMBLE_ROOT)/porting/nimble/src/hal_timer.c \
	$(NIMBLE_ROOT)/porting/nimble/src/os_cputime.c \
	$(NIMBLE_ROOT)/porting/nimble/src/os_cputime_pwr2.c

# Filter out conflicting files from LIB_NIMBLE_SRC
# We replace the OS layer files with our musl-compatible versions
NIMBLE_OBJ_FILTERED := $(filter-out \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_atomic.c \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_atomic.o \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_mutex.c \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_mutex.o \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_eventq.c \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_eventq.o \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_task.c \
	$(BLE_HOST_ROOT)/os/linux_app/src/os_task.o \
	$(NIMBLE_ROOT)/cli/cli.o \
    $(NIMBLE_ROOT)/cli/ble_at_cmd.o \
    $(NIMBLE_ROOT)/apps/main.o \
    $(NIMBLE_ROOT)/apps/ble.o \
    $(NIMBLE_BT_SHELL_SRC) \
    $(NIMBLE_HOST_MESH_SRC) \
    $(NIMBLE_MESH_DEMO_SRC) \
	,$(LIB_NIMBLE_SRC))

# All source files
SRC := $(OS_SRC) $(NIMBLE_OBJ_FILTERED)

# Include paths - must come BEFORE Makefile_host.include sets CONFIG-dependent paths
INC := \
	. \
	$(OS_DIR) \
	$(BLE_HOST_ROOT)/include \
	$(BLE_HOST_ROOT)/os/linux_app/include \
	$(NIMBLE_ROOT)/apps \
	$(NIMBLE_ROOT)/cli \
	$(NIMBLE_ROOT)/nimble/transport/ioctl/include \
	$(NIMBLE_ROOT)/ext/tinycrypt/include \
	$(NIMBLE_ROOT)/nimble/include \
	$(NIMBLE_ROOT)/nimble/controller/include \
	$(NIMBLE_ROOT)/nimble/host/include \
	$(NIMBLE_ROOT)/nimble/host/mesh/include \
	$(NIMBLE_ROOT)/nimble/host/services/include \
	$(NIMBLE_ROOT)/nimble/host/src \
	$(NIMBLE_ROOT)/nimble/host/store/config/include \
	$(NIMBLE_ROOT)/nimble/host/util/include \
	$(NIMBLE_ROOT)/nimble/transport/uart/include \
	$(NIMBLE_ROOT)/porting/nimble/include \
	$(NIMBLE_ROOT)/nimble/host/services/ans/include \
	$(NIMBLE_ROOT)/nimble/host/services/bas/include \
	$(NIMBLE_ROOT)/nimble/host/services/gap/include \
	$(NIMBLE_ROOT)/nimble/host/services/gatt/include \
	$(NIMBLE_ROOT)/nimble/host/services/ias/include \
	$(NIMBLE_ROOT)/nimble/host/services/lls/include \
	$(NIMBLE_ROOT)/nimble/host/services/tps/include \
	$(NIMBLE_ROOT)/nimble/host/services/dis/include \
	$(NIMBLE_ROOT)/nimble/transport/ram/include \
	$(NIMBLE_ROOT)/nimble/drivers/juno/src \
	$(NIMBLE_ROOT)/nimble/host/store/ram/include \
	$(NIMBLE_ROOT)/nimble/host/mesh/src

INCLUDES := $(addprefix -I, $(INC))

# Object files
# LIB_NIMBLE_SRC contains .o paths, convert them to .c for compilation
SRC_C  := $(filter %.c,  $(SRC))
SRC_O  := $(filter %.o,  $(SRC))
# Convert .o back to .c for sources that need compilation
SRC_FROM_O := $(SRC_O:.o=.c)
# Combine all C sources and generate object list
ALL_SRC_C := $(SRC_C) $(SRC_FROM_O)
OBJ := $(ALL_SRC_C:.c=.o)
# NIMBLE_EXT_SRC also has .o paths, keep them as the target objects
TINYCRYPT_OBJ := $(NIMBLE_EXT_SRC)

# Compiler flags
CFLAGS := \
	$(NIMBLE_CFLAGS) \
	$(INCLUDES) \
	-g \
	-D_GNU_SOURCE \
	-D__WORDSIZE=32 \
	-Os \
	-fPIC \
	-DCONFIG_LINUX_BLE_STACK_APP=1 \
	-DCONFIG_BLE_PTS_TEST_MOD=0 \
	-Wno-return-mismatch \
	-include stdlib.h \
	-include sys/ioctl.h \
	-include $(OS_DIR)/os_npl_extensions.h

# Linker flags for shared library
LDFLAGS := ${TARGET_LDFLAGS} -shared -fPIC
LIBS := $(NIMBLE_LDFLAGS) -lrt -lpthread

# Library output
LIBRARY := libnimble.so
LIBRARY_VERSION := libnimble.so.1.0.0

# Targets
.PHONY: all clean install-staging install-target

all: $(LIBRARY)

clean:
	rm -f $(OBJ) $(TINYCRYPT_OBJ)
	rm -f $(LIBRARY) $(LIBRARY_VERSION)

# Install to staging: library + headers (for compilation of other packages)
install-staging: $(LIBRARY)
	mkdir -p $(DESTDIR)/usr/lib
	mkdir -p $(DESTDIR)/usr/include/nimble
	mkdir -p $(DESTDIR)/usr/include/host
	mkdir -p $(DESTDIR)/usr/include/host/util
	mkdir -p $(DESTDIR)/usr/include/syscfg
	mkdir -p $(DESTDIR)/usr/include/sysflash
	mkdir -p $(DESTDIR)/usr/include/logcfg
	cp -f $(LIBRARY_VERSION) $(DESTDIR)/usr/lib/
	ln -sf $(LIBRARY_VERSION) $(DESTDIR)/usr/lib/$(LIBRARY)
	# Install headers needed by libblepp (staging only)
	cp -f $(NIMBLE_ROOT)/nimble/host/include/host/*.h $(DESTDIR)/usr/include/host/
	cp -f $(NIMBLE_ROOT)/nimble/host/util/include/host/util/util.h $(DESTDIR)/usr/include/host/util/
	cp -f -r $(NIMBLE_ROOT)/nimble/include/* $(DESTDIR)/usr/include
	cp -f -r $(NIMBLE_ROOT)/porting/nimble/include/* $(DESTDIR)/usr/include
	cp -f -r $(BLE_HOST_ROOT)/os/linux_app/include/* $(DESTDIR)/usr/include
	cp -f $(BLE_HOST_ROOT)/include/*.h $(DESTDIR)/usr/include/
	cp -f $(NIMBLE_ROOT)/porting/nimble/include/nimble/nimble_port.h $(DESTDIR)/usr/include/nimble/

# Install to target: library only (no headers needed at runtime)
install-target: $(LIBRARY)
	mkdir -p $(DESTDIR)/usr/lib
	cp -f $(LIBRARY_VERSION) $(DESTDIR)/usr/lib/
	ln -sf $(LIBRARY_VERSION) $(DESTDIR)/usr/lib/$(LIBRARY)

# Compilation rules
$(TINYCRYPT_OBJ): CFLAGS+=$(TINYCRYPT_CFLAGS)

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

# Link shared library
$(LIBRARY_VERSION): $(OBJ) $(TINYCRYPT_OBJ)
	$(LD) $(LDFLAGS) -Wl,-soname,$(LIBRARY) -o $@ $^ $(LIBS)
	$(SIZE) $@
	@echo ""
	@echo "========================================="
	@echo "Build complete: $(LIBRARY_VERSION)"
	@echo "========================================="
	@echo ""

$(LIBRARY): $(LIBRARY_VERSION)
	ln -sf $(LIBRARY_VERSION) $(LIBRARY)
