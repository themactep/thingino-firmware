# Makefile for wolfSSL certificate generator
# This builds a simple certificate generation utility using wolfSSL

CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
LDFLAGS ?=
LIBS = -lwolfssl

# Add wolfSSL include and library paths for cross-compilation
ifdef STAGING_DIR
CFLAGS += -I$(STAGING_DIR)/usr/include
LDFLAGS += -L$(STAGING_DIR)/usr/lib
endif

# Force wolfSSL linking since it's a build dependency
TARGET = wolfssl-certgen
SOURCE = wolfssl-certgen.c

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SOURCE)
	@echo "Building $(TARGET) with wolfSSL support..."
	$(CC) $(CFLAGS) -DHAVE_WOLFSSL $(SOURCE) -o $(TARGET) $(LDFLAGS) $(LIBS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)

# Test target to verify the binary works
test: $(TARGET)
	./$(TARGET) --help
