# Makefile for wolfSSL certificate generator
# This builds a simple certificate generation utility using wolfSSL

CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
LDFLAGS ?=
LIBS = -lwolfssl

# Check if wolfSSL is available
WOLFSSL_AVAILABLE := $(shell pkg-config --exists wolfssl && echo yes || echo no)

TARGET = wolfssl-certgen
SOURCE = wolfssl-certgen.c

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SOURCE)
ifeq ($(WOLFSSL_AVAILABLE),yes)
	@echo "Building $(TARGET) with wolfSSL support..."
	$(CC) $(CFLAGS) -DHAVE_WOLFSSL $(SOURCE) -o $(TARGET) $(LDFLAGS) $(LIBS)
else
	@echo "Warning: wolfSSL not found, building fallback version..."
	$(CC) $(CFLAGS) $(SOURCE) -o $(TARGET) $(LDFLAGS)
endif

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)

# Test target to verify the binary works
test: $(TARGET)
	./$(TARGET) --help
