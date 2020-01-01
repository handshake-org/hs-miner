#ifndef _HS_HEADER_H
#define _HS_HEADER_H

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct hs_header_s {
  // Preheader.
  uint32_t nonce;
  uint64_t time;
  uint8_t padding[20];
  uint8_t prev_block[32];
  uint8_t name_root[32];

  // Mask Hash.
  uint8_t mask_hash[32];

  // Subheader.
  uint8_t extra_nonce[24];
  uint8_t reserved_root[32];
  uint8_t witness_root[32];
  uint8_t merkle_root[32];
  uint32_t version;
  uint32_t bits;
} hs_header_t;

void
hs_header_init(hs_header_t *hdr);

hs_header_t *
hs_header_alloc(void);

bool
hs_header_read(uint8_t **data, size_t *data_len, hs_header_t *hdr);

bool
hs_header_decode(const uint8_t *data, size_t data_len, hs_header_t *hdr);

int
hs_header_write(const hs_header_t *hdr, uint8_t **data);

int
hs_header_size(const hs_header_t *hdr);

int
hs_header_encode(const hs_header_t *hdr, uint8_t *data);

int
hs_header_pre_write(const hs_header_t *hdr, uint8_t **data);

int
hs_header_pre_size(const hs_header_t *hdr);

int
hs_header_pre_encode(const hs_header_t *hdr, uint8_t *data);

int
hs_header_sub_write(const hs_header_t *hdr, uint8_t **data);

int
hs_header_sub_size(const hs_header_t *hdr);

int
hs_header_sub_encode(const hs_header_t *hdr, uint8_t *data);

void
hs_header_sub_hash(const hs_header_t *hdr, uint8_t *hash);

void
hs_header_padding(const hs_header_t *hdr, uint8_t *pad, size_t size);

void
hs_header_pow(hs_header_t *hdr, uint8_t *hash);

int
hs_header_verify_pow(const hs_header_t *hdr, uint8_t *target);

void
hs_header_print(hs_header_t *hdr, const char *prefix);

#if defined(__cplusplus)
}
#endif

#endif
