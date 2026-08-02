# Makefile for daynightd - Day/Night Mode Switching Daemon
# Optimized for MIPS Ingenic XBurst embedded systems

CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -Wextra -O2 -std=c99 -D_GNU_SOURCE
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -DNDEBUG
LDFLAGS = -Wl,--gc-sections -s
LIBS = -ljct -lm

SRCDIR = .
SOURCES = $(SRCDIR)/daynightd.c
TARGET = daynightd

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(LIBS)

dev: CC = gcc
dev: CFLAGS = -Wall -Wextra -g -std=c99 -D_GNU_SOURCE -DDEBUG
dev: LDFLAGS =
dev: LIBS = -ljct -lm
dev: $(TARGET)

clean:
	rm -f $(TARGET)
