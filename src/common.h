#ifndef _HS_MINER_COMMON_H
#define _HS_MINER_COMMON_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "header.h"
#include "sha3.h"
#include "blake2b.h"

#define MIN_HEADER_SIZE 4

#ifndef MAX_HEADER_SIZE
#define MAX_HEADER_SIZE 512
#endif

#ifndef HS_NETWORK
#define HS_NETWORK main
#endif

#define HS_QUOTE(name) #name
#define HS_STR(macro) HS_QUOTE(macro)

#define HS_SUCCESS 0
#define HS_ENOMEM 1
#define HS_EFAILURE 2
#define HS_EBADARGS 3
#define HS_ENODEVICE 4
#define HS_EBADPROPS 5
#define HS_ENOSUPPORT 6
#define HS_EMAXLOAD 7
#define HS_EBADPATH 8
#define HS_ENOSOLUTION 9

typedef struct hs_options_s {
  size_t header_len;
  uint32_t nonce;
  uint32_t range;
  uint8_t target[32];
  uint32_t threads;
  uint32_t device;
  bool log;
  bool is_cuda;
  bool running;
  uint8_t header[MAX_HEADER_SIZE];
} hs_options_t;

typedef int32_t (*hs_miner_func)(
  hs_options_t *options,
  uint32_t *result,
  bool *match
);

#ifdef HS_HAS_CUDA
typedef struct hs_device_info_s {
  char name[513];
  uint64_t memory;
  uint32_t bits;
  uint32_t clock_rate;
} hs_device_info_t;
#endif

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
);

#ifdef HS_HAS_CUDA
uint32_t
hs_device_count(void);

bool
hs_device_info(uint32_t device, hs_device_info_t *info);

int32_t
hs_cuda_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
);

int32_t
hs_verify(
  const hs_header_t *hdr,
  const uint8_t *target
);

static inline uint32_t
hs_read_u32(const uint8_t *data) {
  uint32_t out;
#ifdef HS_LITTLE_ENDIAN
  memcpy(&out, data, 4);
#else
  out = 0;
  out |= ((uint32_t)data[3]) << 24;
  out |= ((uint32_t)data[2]) << 16;
  out |= ((uint32_t)data[1]) << 8;
  out |= (uint32_t)data[0];
#endif
  return out;
}

static inline void
hs_write_u32(uint8_t *data, uint32_t num) {
#ifdef HS_LITTLE_ENDIAN
  memcpy(data, &num, 4);
#else
  data[0] = (uint8_t)num;
  data[1] = (uint8_t)(num >> 8);
  data[2] = (uint8_t)(num >> 16);
  data[3] = (uint8_t)(num >> 24);
#endif
}
#endif

#endif
