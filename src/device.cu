#include <assert.h>
#include <stdbool.h>
#include "common.h"

uint32_t
hs_device_count(void) {
  int32_t device_count = 0;

  cudaGetDeviceCount(&device_count);

  if (device_count < 0)
    return 0;

  return device_count;
}

bool
hs_device_info(uint32_t device, hs_device_info_t *info) {
  assert(info);

  int32_t device_count = 0;

  cudaGetDeviceCount(&device_count);

  if (device_count < 0 || device >= device_count)
    return false;

  cudaDeviceProp prop;
  cudaGetDeviceProperties(&prop, device);

  if (strlen(prop.name) > 512)
    return false;

  strcpy(info->name, prop.name);

  info->memory = prop.totalGlobalMem;
  info->bits = prop.memoryBusWidth;
  info->clock_rate = prop.memoryClockRate;

  return true;
}
