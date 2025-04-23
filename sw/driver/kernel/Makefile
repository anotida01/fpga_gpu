
obj-m += gpu_driver.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean


flow:
	rmmod gpu_driver
	insmod gpu_driver.ko
