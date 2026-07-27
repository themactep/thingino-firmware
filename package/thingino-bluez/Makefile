# SPDX-License-Identifier: GPL-2.0
# Simplified Makefile for building libbluetooth shared library

# Compiler and flags
CC ?= gcc
LD ?= $(CC)

CFLAGS = -Wall -Wextra -O2 -fPIC
LDFLAGS ?= -shared
INCLUDES = -Ilib

# Library name and version
LIBNAME = libbluetooth.so.3
LIBNAME_SHORT = libbluetooth.so

# Source files from lib/
LIB_DIR = lib
SOURCES = $(LIB_DIR)/bluetooth.c \
          $(LIB_DIR)/hci.c \
          $(LIB_DIR)/uuid.c

# Object files
OBJECTS = $(SOURCES:.c=.o)

# Default target
all: $(LIBNAME)

# Build the shared library
$(LIBNAME): $(OBJECTS)
	@echo "Creating shared library: $@"
	$(LD) $(LDFLAGS) -Wl,-soname,$(LIBNAME) -o $@ $^

# Compile source files to object files
%.o: %.c
	@echo "Compiling: $<"
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Clean target
clean:
	rm -f $(OBJECTS) $(LIBNAME)

.PHONY: all clean