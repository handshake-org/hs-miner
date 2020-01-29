#ifndef _HS_MINER_COMMON_H
#define _HS_MINER_COMMON_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "header.h"
#include "sha3.h"
#include "blake2b.h"

#ifdef __cplusplus
extern "C" {
#endif

#define HEADER_SIZE 256
#define EXTRA_NONCE_SIZE 24

#ifndef HS_NETWORK
#define HS_NETWORK main
#endif

#define HS_QUOTE(name) #name
#define HS_STR(macro) HS_QUOTE(macro)

typedef struct hs_options_s {
  size_t header_len;
  uint32_t nonce;
  uint32_t range;
  uint8_t target[32];
  uint32_t grids;
  uint32_t blocks;
  uint32_t threads;
  uint32_t device;
  bool log;
  bool is_cuda;
  bool running;
  uint8_t header[HEADER_SIZE];
} hs_options_t;

typedef int32_t (*hs_miner_func)(
  hs_options_t *options,
  uint32_t *result,
  uint8_t *extra_nonce,
  bool *match
);

typedef struct hs_device_info_s {
  char name[513];
  uint64_t memory;
  uint32_t bits;
  uint32_t clock_rate;
} hs_device_info_t;

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  uint8_t *extra_nonce,
  bool *match
);

#ifdef HS_HAS_CUDA
uint32_t
hs_cuda_device_count(void);

bool
hs_cuda_device_info(uint32_t device, hs_device_info_t *info);

int32_t
hs_cuda_run(
  hs_options_t *options,
  uint32_t *result,
  uint8_t *extra_nonce,
  bool *match
);
#endif

#ifdef HS_HAS_OPENCL
uint32_t
hs_opencl_device_count();

bool
hs_opencl_device_info(uint32_t device, hs_device_info_t *info);

int32_t
hs_opencl_run(
  hs_options_t *options,
  uint32_t *result,
  uint8_t *extra_nonce,
  bool *match
);
#endif

int32_t
hs_verify(
  hs_header_t *hdr,
  uint8_t *target
);

#ifdef __cplusplus
}
#endif

#endif
