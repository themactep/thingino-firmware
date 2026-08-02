# Makefile for floodlightd - Wyze Floodlight v2 CH554 MCU daemon
# MIPS Ingenic XBurst (T41), thingino

CC ?= $(CROSS_COMPILE)gcc
CFLAGS ?= -Wall -Wextra -O2 -std=c99 -D_GNU_SOURCE
CFLAGS += -ffunction-sections -fdata-sections -DNDEBUG
LDFLAGS ?= -Wl,--gc-sections -s

TARGET  = floodlightd
SOURCES = floodlightd.c

PREFIX     ?= /usr
BINDIR      = $(PREFIX)/bin
SYSCONFDIR  = /etc
INITDIR     = /etc/init.d

.PHONY: all clean install dev

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# native build for host testing
dev: CC = gcc
dev: CFLAGS = -Wall -Wextra -g -std=c99 -D_GNU_SOURCE -DDEBUG
dev: LDFLAGS =
dev: $(TARGET)

install: $(TARGET)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/
	ln -sf $(TARGET) $(DESTDIR)$(BINDIR)/floodlightctl

clean:
	rm -f $(TARGET)
