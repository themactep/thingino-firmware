#
# Thingino Bluetooth - BLE GATT Server Makefile
#
# Builds ble-provision using libble++ C++ SDK
#

CROSS_COMPILE ?= mips-linux-gnu-
CXX     := $(CROSS_COMPILE)g++
CC      := $(CROSS_COMPILE)gcc
LD      := $(CROSS_COMPILE)g++
AR      := $(CROSS_COMPILE)ar
STRIP   := $(CROSS_COMPILE)strip

# Target executable
TARGET := ble-provision

# Source files
SOURCES := ble-provision.cc improv/improv.cpp

# Object files (replace both .cc and .cpp with .o)
OBJ := $(patsubst %.cc,%.o,$(patsubst %.cpp,%.o,$(SOURCES)))

# libble++ configuration
LIBBLE_ROOT ?= $(abspath ../../thingino-libble)
LIBBLE_INCLUDE := $(LIBBLE_ROOT)/include
LIBBLE_LIB := $(LIBBLE_ROOT)/lib/libble++.so

# Include paths
INCLUDES := \
	-I. \
	-I$(LIBBLE_INCLUDE)

# Compiler flags
CXXFLAGS := \
	-std=c++11 \
	-Os \
	-fPIC \
	-Wall \
	-Wno-deprecated-declarations \
	-DBLEPP_NIMBLE_SUPPORT \
	-DBLEPP_SERVER_SUPPORT \
	$(INCLUDES)

CFLAGS := \
	-Os \
	-fPIC \
	-Wall \
	$(INCLUDES)

# Linker flags
LDFLAGS := -L$(LIBBLE_ROOT)/lib
LIBS := -lble++ -lpthread -lstdc++ -lrt

# Default target
.PHONY: all clean install

all: $(TARGET)

# Link executable
$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $^ $(LIBS)
	$(STRIP) $@ --strip-unneeded
	@echo ""
	@echo "========================================="
	@echo "Build complete: $(TARGET)"
	@echo "========================================="
	@echo ""

# Compile C++ sources (.cc)
%.o: %.cc
	$(CXX) -c $(CXXFLAGS) -o $@ $<

# Compile C++ sources (.cpp)
%.o: %.cpp
	$(CXX) -c $(CXXFLAGS) -o $@ $<

clean:
	rm -f $(OBJ) $(TARGET)

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)

.PHONY: all clean install
