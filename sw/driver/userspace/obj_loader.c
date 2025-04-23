#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/eventfd.h>
#include "../address_map_arm.h"
#include "../gpu.h"

// Function prototypes
int gpu_write_mem(char *argv[]);
int gpu_start();

// globals
int gpu_fd;

int main(int argc, char *argv[]) {

  // open gpu chardev
  gpu_fd = open("/dev/gpu", O_RDWR);
  if (gpu_fd == -1) {
    perror("failed to open gpu chardev");
    return 1;
  }

  // register interrupt wait period
  int efd = eventfd(0, 0); // EFD_NONBLOCK is optional

  if (efd == -1) {
    perror("failed to create eventfd object");
    return 1;
  }
  
  // Pass the eventfd to the kernel module
  if (ioctl(gpu_fd, GPU_IOCTL_PASS_EVENTFD, &efd) < 0) {
    perror("ioctl failed to pass efd to kernel");
    return 1;
  }

  // check args
  if (argc != 2) {
    fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
    return 1;
  }

  // write out the object to GPU MEM
  gpu_write_mem(argv);

  // now we need to render a frame. we can modify the kernel driver so that we can send commands such as modify rotation etc?
  // the simple goal for now should be to create an application that rotates the drawn object. we can also make it interactive with the keyboard!

  gpu_start(); // start drawing

  printf("Waiting for eventfd signal...\n");
  uint64_t value;
  read(efd, &value, sizeof(value));  // This blocks until signaled

  printf("GPU is done. Program exiting...\n");

  close(gpu_fd);

  return 0;
}


/**
 * @brief Reads hex values from a file, converts them to unsigned integers, and writes them to the GPU's memory.
 *
 * This function opens a specified file, counts the number of lines to determine the array size,
 * allocates memory for an unsigned integer array, reads hex strings from each line of the file,
 * converts them to unsigned integers using `strtoul`, and writes the resulting array to the GPU's memory
 * using the `/dev/gpu` device. Error handling is included for file opening, memory allocation,
 * hex string conversion, and writing to the GPU.
 *
 * @param argv An array of strings representing the command-line arguments. The first argument
 *             (argv[1]) is expected to be the filename containing the hex values.
 * @return 0 on success, 1 on failure.
 */
int gpu_write_mem(char *argv[]){

  const char *filename = argv[1];
  FILE *file = fopen(filename, "r");

  if (file == NULL) {
    perror("Error opening file");
    return 1;
  }

  // Count the number of lines in the file to determine the array size
  int numLines = 0;
  char buffer[255]; // Adjust the buffer size accordingly
  while (fgets(buffer, sizeof(buffer), file) != NULL) {
    numLines++;
  }

  // Allocate memory for the array
  unsigned int *hexArray = (unsigned int *)malloc(numLines * sizeof(unsigned int));
  if (hexArray == NULL) {
    fclose(file);
    perror("Memory allocation error");
    return 1;
  }

  // Reset file position indicator to the beginning of the file
  rewind(file);

  // Read hex strings and convert to unsigned integers
  for (int i = 0; i < numLines; i++) {
    if (fgets(buffer, sizeof(buffer), file) == NULL) {
      fprintf(stderr, "Error reading line %d from file\n", i + 1);
      free(hexArray);
      fclose(file);
      return 1;
    }

    // Convert hex string to unsigned int
    char *endptr;
    hexArray[i] = strtoul(buffer, &endptr, 16);

    // Check for conversion errors
    if (*endptr != '\0' && *endptr != '\n') {
      fprintf(stderr, "Error converting hex string on line %d\n", i + 1);
      free(hexArray);
      fclose(file);
      return 1;
    }
  }

  // Close the file
  fclose(file);

  ssize_t bytes_written = write(gpu_fd, hexArray, numLines*4);

  if (bytes_written != numLines*4){
    perror("Failed to write GPU Object to GPU MEM\n");
    return 1;
  }

  printf("Completed writing to SDRAM. Reading back...\n");
  return 0;
}


/**
 * @brief Starts the GPU processing after data has been written.
 *
 * This function opens the `/dev/gpu` device in write-only mode,
 * sends the `GPU_IOCTL_START` ioctl to initiate GPU processing, and then closes the device.
 *
 * @return 0 on success, 1 on failure.
 */
int gpu_start(){
  return ioctl(gpu_fd, GPU_IOCTL_START);
}
