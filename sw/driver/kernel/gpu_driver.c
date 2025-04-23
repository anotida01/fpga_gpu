/**
 * @file sw/driver/kernel/gpu_driver.c
 * @brief Kernel driver for the FPGA GPU.
 */

#include <linux/module.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/io.h>
#include <linux/vmalloc.h>
#include <linux/uaccess.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/types.h>
#include <linux/interrupt.h>
#include <linux/eventfd.h>

// local headers
#include "../gpu.h"
#include "../gpu_regs.h"
#include "../address_map_arm.h"
#include "../interrupt_ID.h"

#define DEVICE_NAME "gpu"
#define CLASS_NAME  "gpu_class"

/* globals */
static int    major_number;
static struct class*  gpu_class  = NULL;
static struct device* gpu_device = NULL;
static struct cdev    gpu_cdev;
static volatile uint32_t* gpu_ctrl_ptr = NULL;
static volatile gpu_ctrl_t* gpu_ctrl;
static volatile void* lw_bridge_ptr = NULL;
static struct eventfd_ctx *efd_ctx = NULL;

/* function prototypes */
static int  gpu_open(struct inode *, struct file *);
static int  gpu_release(struct inode *, struct file *);
static long gpu_ioctl(struct file *, unsigned int, unsigned long);
static int  gpu_write(struct file *file, const char __user *buf, size_t count, loff_t *ppos);
static irq_handler_t gpu_irq_handler(int irq, void *dev_id, struct pt_regs *regs);
static int gpu_set_eventfd(unsigned long arg);

/* chardev file ops struct */
static struct file_operations fops = {
  .owner          = THIS_MODULE,
  .open           = gpu_open,
  .release        = gpu_release,
  .write          = gpu_write,
  .unlocked_ioctl = gpu_ioctl,
};


/**
 * @brief Initializes the GPU driver.
 *
 * @return 0 on success, negative error code on failure.
 */
static int __init gpu_init(void) {
  printk(KERN_INFO "FPGA_GPU: Initializing the driver\n");

  /* Initialize GPU chardev*/
  // get major number
  major_number = register_chrdev(0, DEVICE_NAME, &fops);
  if (major_number < 0) {
    printk(KERN_ALERT "FPGA_GPU: Failed to register a major number\n");
    return major_number;
  }
  printk(KERN_INFO "FPGA_GPU: Registered with major number %d\n", major_number);

  // register class
  gpu_class = class_create(THIS_MODULE, CLASS_NAME);
  if (IS_ERR(gpu_class)) {
    unregister_chrdev(major_number, DEVICE_NAME);
    printk(KERN_ALERT "FPGA_GPU: Failed to register device class\n");
    return PTR_ERR(gpu_class);
  }

  // create the device
  gpu_device = device_create(gpu_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
  if (IS_ERR(gpu_device)) {
    class_destroy(gpu_class);
    unregister_chrdev(major_number, DEVICE_NAME);
    printk(KERN_ALERT "FPGA_GPU: Failed to create the device\n");
    return PTR_ERR(gpu_device);
  }
  cdev_init(&gpu_cdev, &fops);
  cdev_add(&gpu_cdev, MKDEV(major_number, 0), 1);
  printk(KERN_INFO "FPGA_GPU: Device created successfully\n");

  /* Map GPU CTRL HW address to kernel VM*/
  // get a ptr to FPGA LW Bridge
  lw_bridge_ptr = ioremap_nocache(LW_BRIDGE_BASE, LW_BRIDGE_SPAN);

  if (lw_bridge_ptr == NULL) {
    printk(KERN_ERR "FPGA_GPU: Failed to map ptr to GPU CTRL base address (ioremap_nocache)\n");
    return -EIO;
  } else {
    printk(KERN_INFO "FPGA_GPU: Got a ptr to GPU CTRL base address\n");
  }

  // compute actual GPU address
  gpu_ctrl_ptr = (uint32_t*)(lw_bridge_ptr + GPU_BASE);
  gpu_ctrl = (gpu_ctrl_t*)gpu_ctrl_ptr;

  /* initialize interrupts and irq handler */
  if(request_irq(GPU_IRQ, (irq_handler_t) gpu_irq_handler, IRQF_SHARED, "gpu_irq_handler", (void *) (gpu_irq_handler))) {
    printk(KERN_ERR "FPGA_GPU: Failed to register interrupt# %d", GPU_IRQ);
    return -EBUSY;
  }

  printk(KERN_INFO "FPGA_GPU: Initialization is complete!\n");
  return 0;
}


/**
 * @brief Cleans up the GPU driver.
 */
static void __exit gpu_exit(void) {
  cdev_del(&gpu_cdev);
  device_destroy(gpu_class, MKDEV(major_number, 0));
  class_unregister(gpu_class);
  class_destroy(gpu_class);
  unregister_chrdev(major_number, DEVICE_NAME);

  iounmap(lw_bridge_ptr);
  free_irq (GPU_IRQ, (void*) gpu_irq_handler);

  if (efd_ctx) eventfd_ctx_put(efd_ctx);

  printk(KERN_INFO "FPGA_GPU: Goodbye from the driver\n");
}


static int gpu_set_eventfd(unsigned long arg) {
  int efd;
  struct eventfd_ctx* ctx;

  // if (efd_ctx != NULL) return -EBUSY; // only support 1 for now

  if (copy_from_user(&efd, (int __user *)arg, sizeof(efd)))
    return -EFAULT;

  ctx = eventfd_ctx_fdget(efd);
  if (IS_ERR(ctx))
    return PTR_ERR(ctx);

  efd_ctx = ctx;
  printk(KERN_INFO "FPGA_GPU: eventfd set\n");
  return 0;
}


/**
 * @brief Opens the GPU device.
 *
 * @param inodep Inode of the device.
 * @param filep File pointer.
 * @return 0 on success.
 */
static int gpu_open(struct inode *inodep, struct file *filep) {
  printk(KERN_INFO "FPGA_GPU: Device opened\n");
  return 0;
}


/**
 * @brief Closes the GPU device.
 *
 * @param inodep Inode of the device.
 * @param filep File pointer.
 * @return 0 on success.
 */
static int gpu_release(struct inode *inodep, struct file *filep) {
    printk(KERN_INFO "FPGA_GPU: Device closed\n");
    return 0;
}


/**
 * @brief Handles IOCTL calls for the GPU device.
 *
 * @param filep File pointer.
 * @param cmd IOCTL command.
 * @param arg Argument for the IOCTL command.
 * @return 0 on success.
 */
static long gpu_ioctl(struct file *filep, unsigned int cmd, unsigned long arg) {
  uint32_t return_val = 0;
  printk(KERN_INFO "FPGA_GPU: IOCTL called - cmd: %u, arg: %lu\n", cmd, arg);

    switch (cmd){
      case GPU_IOCTL_START:
        gpu_ctrl->GPU_CTRL.f.GPU_START = 0x1U;
        return_val = 0;
        break;
      case GPU_IOCTL_PASS_EVENTFD:
        return_val = gpu_set_eventfd(arg);
        if (return_val != 0)
          printk(KERN_ERR "FPGA_GPU: Failed to set eventfd, ERRNO: %d", return_val);
        break;
      default:
        printk(KERN_ERR "FPGA_GPU: Last IOCTL cmd is not valid");
        break;
    }

    return return_val;
}


/**
 * @brief Writes data to the GPU character device.
 *
 * This function is called when data is written to the GPU character device.
 *
 * @param file A pointer to the file structure.
 * @param buf A pointer to the user buffer containing the data to write.
 * @param count The number of bytes to write.
 * @param ppos A pointer to the file offset.
 *
 * @return The number of bytes written.
 */
static int gpu_write(struct file *file, const char __user *buf, size_t count, loff_t *ppos)
{
  void* kernel_buf;
  void* gpu_mem_ptr;
  printk(KERN_INFO "FPGA_GPU: Chardev Write function called - file: 0x%p, buf: %p, count: 0x%x\n", file, buf, count);

  // create a kernel buffer and copy the bytes from memory, this will be a mem to mem cpy
  kernel_buf = vmalloc(count);
  if (kernel_buf == NULL){
    printk(KERN_ERR "FPGA_GPU: Failed to allocate kernel buffer of %d bytes\n", count);
    return -ENOMEM;
  } else {
    printk(KERN_INFO "FPGA_GPU: Allocated kernel buffer of %d bytes\n", count);
  }

  // copy the object from userspace to kernel buffer
  // TODO: Can we skip this?
  if (copy_from_user(kernel_buf, buf, count) != 0) {
    printk(KERN_ERR "FPGA_GPU: Failed to copy user buffer to kernel buffer\n");
    kvfree(kernel_buf);
    return -EFAULT;
  }
  printk(KERN_INFO "FPGA_GPU: Copied user buffer to kernel buffer\n");

  // perform the copy to gpu memory
  printk(KERN_INFO "FPGA_GPU: Attempting to copy data to GPU\n");
  gpu_mem_ptr = ioremap_nocache(SDRAM_BASE, SDRAM_SPAN);
  memcpy(gpu_mem_ptr, kernel_buf, count);
  wmb(); // mem ops barrier

  // cleanup
  printk(KERN_INFO "FPGA_GPU: Data copied to GPU. Cleaning up\n");
  iounmap(gpu_mem_ptr);
  kvfree(kernel_buf);

  return count;
}


/**
 * @brief Interrupt handler for the GPU.
 *
 * This function is called when a GPU interrupt occurs. It retrieves the interrupt
 * status, attempts to clear the interrupt, and verifies that the interrupt has
 * been cleared.
 *
 * @param irq The interrupt number.
 * @param dev_id Device identifier (not used in this implementation).
 * @param regs The register state at the time of the interrupt.
 *
 * @return IRQ_HANDLED if the interrupt was handled successfully, IRQ_NONE otherwise.
 */
irq_handler_t gpu_irq_handler(int irq, void *dev_id, struct pt_regs *regs){
  uint32_t reg_val;
  printk(KERN_INFO "FPGA_GPU: Interrupt triggered, IRQ: %d\n", irq);

  if (efd_ctx) {
    printk(KERN_INFO "FPGA_GPU: Signaling eventfd...\n");
    eventfd_signal(efd_ctx, 1); // Value 1 is added to eventfd counter
    eventfd_ctx_put(efd_ctx); // release here? This might not work for signalling many frames per second TODO
  }

  // get INTR STATUS
  reg_val = gpu_ctrl->GPU_INTR_STATUS.f.GPU_DONE_STAT;
  printk(KERN_INFO "FPGA_GPU: Value of GPU_INT_STATUS: 0x%x\n", reg_val);

  // clear the interrupt
  gpu_ctrl->GPU_INTR_CLEAR.f.GPU_DONE_CLR = 0x1U;

  // check if the interrupt is cleared
  if (gpu_ctrl->GPU_INTR_STATUS.f.GPU_DONE_STAT != 0){
    // todo: we should considering trying to clear here a couple of times
    printk(KERN_ERR "Interrupt did not clear. HW ERR? GPU_INT_STATUS: 0x%x\n", reg_val);
    return (irq_handler_t) IRQ_NONE;
  }

  return (irq_handler_t) IRQ_HANDLED;
}

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Basic Character Driver for FPGA GPU");
MODULE_VERSION("0.1");

module_init(gpu_init);
module_exit(gpu_exit);
