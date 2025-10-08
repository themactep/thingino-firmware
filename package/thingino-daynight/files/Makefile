# Makefile for daynightd - Day/Night Mode Switching Daemon
# Optimized for MIPS Ingenic XBurst embedded systems

# Compiler and flags for embedded MIPS target
CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -Wextra -O2 -std=c99 -D_GNU_SOURCE
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -DNDEBUG
LDFLAGS = -Wl,--gc-sections -s
LIBS = -ljct

# For cross-compilation, adjust these paths as needed
SYSROOT =
CROSS_COMPILE = /home/paul/output-stable/wyze_cam3_t31x_gc2053_rtl8189ftv/host/bin/mipsel-linux-

# Source and target
SRCDIR = .
SOURCES = $(SRCDIR)/daynightd.c
TARGET = daynightd
CONFIG_FILE = daynightd.json
INIT_SCRIPT = init.d/daynightd

# Installation paths (adjust for target system)
PREFIX = /usr
BINDIR = $(PREFIX)/bin
SYSCONFDIR = /etc
INITDIR = /etc/init.d
RUNDIR = /var/run

# Build rules
.PHONY: all clean install uninstall help

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(LIBS)

# Development build (native compilation for testing)
dev: CC = gcc
dev: CFLAGS = -Wall -Wextra -g -std=c99 -D_GNU_SOURCE -DDEBUG
dev: LDFLAGS =
dev: LIBS = -ljct
dev: $(TARGET)

# Install to target system
install: $(TARGET) $(INIT_SCRIPT)
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(SYSCONFDIR)
	install -d $(DESTDIR)$(INITDIR)
	install -d $(DESTDIR)$(RUNDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/
	install -m 644 $(CONFIG_FILE) $(DESTDIR)$(SYSCONFDIR)/daynightd.json
	install -m 755 $(INIT_SCRIPT) $(DESTDIR)$(INITDIR)/
	@echo "Installation complete."
	@echo "Edit $(SYSCONFDIR)/daynightd.json to configure thresholds."
	@echo "Use $(INITDIR)/$(TARGET) start|stop|restart to control the daemon."

# Uninstall
uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)
	rm -f $(DESTDIR)$(SYSCONFDIR)/daynightd.json
	rm -f $(DESTDIR)$(INITDIR)/$(TARGET)
	@echo "Uninstallation complete."

# Clean build artifacts
clean:
	rm -f $(TARGET)
	rm -rf init.d

# Help
help:
	@echo "Available targets:"
	@echo "  all       - Build daynightd for MIPS target (default)"
	@echo "  dev       - Build for native development/testing"
	@echo "  install   - Install to target system"
	@echo "  uninstall - Remove from target system"
	@echo "  clean     - Remove build artifacts"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  CC        - Compiler (default: mipsel-linux-gcc)"
	@echo "  DESTDIR   - Installation root directory"
	@echo "  PREFIX    - Installation prefix (default: /usr)"
