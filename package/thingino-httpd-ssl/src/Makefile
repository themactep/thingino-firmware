CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?=
LIBS = -lmbedtls -lmbedx509 -lmbedcrypto

TARGET = httpd-ssl
SOURCES = httpd-ssl.c event_server.c
OBJECTS = $(SOURCES:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJECTS) $(TARGET)

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/usr/sbin/$(TARGET)

.PHONY: all clean install

