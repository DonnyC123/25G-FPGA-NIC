SHELL = /bin/bash
#
# optional makefile parameters:
# - DEBUG=<0|1>,	enable verbose debug print-out in the driver
# - config_bar_num=,	eth_xdma pci config bar number
#
TARGET_MODULE:=eth_xdma

ifeq ($(DEBUG),1)
	ccflags-y += -D__LIBXDMA_DEBUG__
endif
ifneq ($(config_bar_num),)
	ccflags-y += -DXDMA_CONFIG_BAR_NUM=$(config_bar_num)
endif

ifneq ($(KERNELRELEASE),)
	$(TARGET_MODULE)-objs := libxdma.o xdma_thread.o eth_main.o eth_netdev.o eth_rx_ring.o eth_tx_ring.o
	obj-m := $(TARGET_MODULE).o
else
	BUILDSYSTEM_DIR:=/lib/modules/$(shell uname -r)/build
	PWD:=$(shell pwd)
all :
	$(MAKE) -C $(BUILDSYSTEM_DIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(BUILDSYSTEM_DIR) M=$(PWD) clean
	@/bin/rm -f *.ko modules.order *.mod.c *.o *.o.ur-safe .*.o.cmd

install: all
	@echo "installing kernel modules to /lib/modules/$(shell uname -r)/eth_xdma ..."
	@mkdir -p -m 755 /lib/modules/$(shell uname -r)/eth_xdma
	@install -v -m 644 *.ko /lib/modules/$(shell uname -r)/eth_xdma
	@depmod -a || true

uninstall:
	@echo "Un-installing /lib/modules/$(shell uname -r)/eth_xdma ..."
	@/bin/rm -rf /lib/modules/$(shell uname -r)/eth_xdma
	@depmod -a

endif
