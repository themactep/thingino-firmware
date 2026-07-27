# Makefile for mbedTLS certificate generator
# This builds a simple certificate generation utility using mbedTLS

CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -std=c99
LDFLAGS ?=
LIBS ?= -lmbedtls -lmbedx509 -lmbedcrypto

# Add mbedTLS include and library paths for cross-compilation
ifdef STAGING_DIR
CFLAGS += -I$(STAGING_DIR)/usr/include
LDFLAGS += -L$(STAGING_DIR)/usr/lib
endif

# Force mbedTLS linking since it's a build dependency
TARGET = mbedtls-certgen
SOURCE = mbedtls-certgen.c

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SOURCE)
	@echo "Building $(TARGET) with mbedTLS support..."
	$(CC) $(CFLAGS) -DHAVE_MBEDTLS $(SOURCE) -o $(TARGET) $(LDFLAGS) $(LIBS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)
