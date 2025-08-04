
#ifndef GPU_H
#define GPU_H

#include <linux/ioctl.h>

// GPU IOCTLs
#define GPU_IOC_MAGIC 'G'
#define GPU_IOCTL_START        _IO (GPU_IOC_MAGIC, 0)
#define GPU_IOCTL_PASS_EVENTFD _IOW(GPU_IOC_MAGIC, 1, int)
#define VGA_IOCTL_SWAP         _IO (GPU_IOC_MAGIC, 2)
#define VGA_IOCTL_PRINT_STAT   _IO (GPU_IOC_MAGIC, 3)
#define VGA_IOCTL_CLR_BACK_BUF _IO (GPU_IOC_MAGIC, 4)

#endif