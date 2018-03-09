#ifndef _HSK_MINER_COMMON_H
#define _HSK_MINER_COMMON_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "tromp/blake2.h"

#ifndef EDGEBITS
#define EDGEBITS 29
#endif

#if EDGEBITS > 31
#error "EDGEBITS too high."
#endif

#ifndef PROOFSIZE
#define PROOFSIZE 42
#endif

#ifndef EASE
#define EASE 50
#endif

#ifndef NEDGES
#define NEDGES ((uint32_t)1 << EDGEBITS)
#endif

#ifndef EDGEMASK
#define EDGEMASK ((uint32_t)NEDGES - 1)
#endif

#ifndef EASINESS
#define EASINESS ((uint32_t)(((uint64_t)EASE * (NEDGES * 2)) / 100))
#endif

#define MIN_HEADER_SIZE 4

#ifndef MAX_HEADER_SIZE
#define MAX_HEADER_SIZE 512
#endif

#ifndef HSK_NETWORK
#define HSK_NETWORK main
#endif

#define HSK_QUOTE(name) #name
#define HSK_STR(macro) HSK_QUOTE(macro)

#define HSK_SUCCESS 0
#define HSK_ENOMEM 1
#define HSK_EFAILURE 2
#define HSK_EBADARGS 3
#define HSK_ENODEVICE 4
#define HSK_EBADPROPS 5
#define HSK_ENOSUPPORT 6
#define HSK_EMAXLOAD 7
#define HSK_EBADPATH 8
#define HSK_ENOSOLUTION 9

typedef struct hsk_options_s {
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
} hsk_options_t;

typedef int32_t (*hsk_miner_func)(
  hsk_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

#ifdef HSK_HAS_CUDA
typedef struct hsk_device_info_s {
  char name[513];
  uint64_t memory;
  uint32_t bits;
  uint32_t clock_rate;
} hsk_device_info_t;
#endif

int32_t
hsk_mean_run(
  hsk_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

int32_t
hsk_lean_run(
  hsk_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

int32_t
hsk_simple_run(
  hsk_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

#ifdef HSK_HAS_CUDA
uint32_t
hsk_device_count(void);

bool
hsk_device_info(uint32_t device, hsk_device_info_t *info);

int32_t
hsk_mean_cuda_run(
  hsk_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);

int32_t
hsk_lean_cuda_run(
  hsk_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
);
#endif

int32_t
hsk_verify(
  uint8_t *hdr,
  size_t hdr_len,
  uint8_t *solution,
  uint8_t *target
);

int32_t
hsk_verify_sol(uint8_t *hdr, size_t hdr_len, uint8_t *solution);

static inline uint32_t
hsk_read_u32(uint8_t *data) {
  uint32_t out;
#ifdef HSK_LITTLE_ENDIAN
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
hsk_write_u32(uint8_t *data, uint32_t num) {
#ifdef HSK_LITTLE_ENDIAN
  memcpy(data, &num, 4);
#else
  data[0] = (uint8_t)num;
  data[1] = (uint8_t)(num >> 8);
  data[2] = (uint8_t)(num >> 16);
  data[3] = (uint8_t)(num >> 24);
#endif
}

static inline void
hsk_hash_solution(uint32_t *sol, uint8_t *hash) {
  uint8_t data[PROOFSIZE * 4];

  for (int32_t i = 0; i < PROOFSIZE; i++)
    hsk_write_u32(&data[i * 4], sol[i]);

  blake2b((void *)hash, 32, (const void *)data, sizeof(data), 0, 0);
}
#endif
