#if EDGEBITS >= 5
#include "tromp/lean_miner.cu"
#endif
#include <unistd.h>
#include <stdbool.h>
#include "common.h"

int32_t
hs_lean_cuda_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
) {
#if EDGEBITS >= 5
  uint8_t header[MAX_HEADER_SIZE];
  size_t header_len = options->header_len;
  uint32_t nonce = options->nonce;
  uint32_t range = 1;
  uint32_t device = options->device;
  uint32_t nthreads = 16384;
  uint32_t ntrims = 32;
  uint32_t tpb = 0;

  if (header_len < MIN_HEADER_SIZE || header_len > MAX_HEADER_SIZE)
    return HS_EBADARGS;

  memcpy(header, options->header, header_len);

  if (options->range)
    range = options->range;

  if (options->threads)
    nthreads = options->threads;

  if (options->trims)
    ntrims = options->trims;

  int32_t device_count;
  cudaGetDeviceCount(&device_count);

  if (device_count < 0 || device >= device_count)
    return HS_ENODEVICE;

  cudaSetDevice(device);

  *result = 0;
  *match = false;

  return lean_run(
    &options->running,
    nthreads,
    ntrims,
    tpb,
    nonce,
    range,
    header,
    header_len,
    options->target,
    solution,
    result,
    match
  );
#else
  return HS_ENOSUPPORT;
#endif
}
