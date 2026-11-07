obj-m += thingino-leds.o

KSRC ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KSRC) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KSRC) M=$(CURDIR) clean
