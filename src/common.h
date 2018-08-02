#ifndef _HS_MINER_COMMON_H
#define _HS_MINER_COMMON_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "tromp/blake2.h"
#include "sha3/sha3.h"

#ifndef EDGEBITS
#define EDGEBITS 29
#endif

#if EDGEBITS > 31
#error "EDGEBITS too high."
#endif

#ifndef PROOFSIZE
#define PROOFSIZE 42
#endif

#ifndef PERC
#define PERC 50
#endif

#ifndef NEDGES
#define NEDGES ((uint32_t)1 << EDGEBITS)
#endif

#ifndef EDGEMASK
#define EDGEMASK ((uint32_t)NEDGES - 1)
#endif

#ifndef EASINESS
#define EASINESS ((uint32_t)(((uint64_t)PERC * (NEDGES * 2)) / 100))
#endif

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
  uint8_t header[MAX_HEADER_SIZE];
  uint32_t nonce;
  uint32_t range;
  uint8_t target[32];
  uint32_t threads;
  uint32_t trims;
  uint32_t device;
  bool log;
  bool is_cuda;
  bool running;
} hs_options_t;

typedef int32_t (*hs_miner_func)(
  hs_options_t *options,
  uint8_t *solution,
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
hs_mean_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

int32_t
hs_lean_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

int32_t
hs_simple_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

#ifdef HS_HAS_CUDA
uint32_t
hs_device_count(void);

bool
hs_device_info(uint32_t device, hs_device_info_t *info);

int32_t
hs_mean_cuda_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

int32_t
hs_lean_cuda_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);
#endif

int32_t
hs_verify(
  const uint8_t *hdr,
  size_t hdr_len,
  const uint8_t *solution,
  const uint8_t *target
);

int32_t
hs_verify_sol(const uint8_t *hdr, size_t hdr_len, const uint8_t *solution);

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

static inline void
hs_pow_hash(const uint8_t *data, size_t data_len, uint8_t *hash) {
  // Old:
  // blake2b((void *)hash, 32, (const void *)data, data_len, NULL, 0);
  hs_sha3_ctx ctx;
  hs_sha3_256_init(&ctx);
  hs_sha3_update(&ctx, data, data_len);
  hs_sha3_final(&ctx, hash);
}

static inline void
hs_hash_solution(const uint32_t *sol, uint8_t *hash) {
  uint8_t data[PROOFSIZE * 4];

  for (int32_t i = 0; i < PROOFSIZE; i++)
    hs_write_u32(&data[i * 4], sol[i]);

  hs_pow_hash(data, sizeof(data), hash);
}
#endif
