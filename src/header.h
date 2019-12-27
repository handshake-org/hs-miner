#ifndef _HS_HEADER_H
#define _HS_HEADER_H

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct hs_header_s {
  // Preheader.
  uint32_t nonce;
  uint64_t time;
  uint8_t prev_block[32];
  uint8_t name_root[32];

  // Subheader.
  uint8_t extra_nonce[24];
  uint8_t reserved_root[32];
  uint8_t witness_root[32];
  uint8_t merkle_root[32];
  uint32_t version;
  uint32_t bits;

  // Mask.
  uint8_t mask[32];

  bool cache;
  uint8_t hash[32];
  uint32_t height;
  uint8_t work[32];

  struct hs_header_s *next;
} hs_header_t;

void
hs_header_init(hs_header_t *hdr);

hs_header_t *
hs_header_alloc(void);

hs_header_t *
hs_header_clone(const hs_header_t *hdr);

bool
hs_pow_to_target(uint32_t bits, uint8_t *target);

bool
hs_pow_to_bits(const uint8_t *target, uint32_t *bits);

bool
hs_header_get_proof(const hs_header_t *hdr, uint8_t *proof);

bool
hs_header_calc_work(hs_header_t *hdr, const hs_header_t *prev);

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
hs_header_mask_hash(const hs_header_t *hdr, uint8_t *hash);

void
hs_header_commit_hash(const hs_header_t *hdr, uint8_t *hash);

void
hs_header_padding(const hs_header_t *hdr, uint8_t *pad, size_t size);

bool
hs_header_equal(hs_header_t *a, hs_header_t *b);

const uint8_t *
hs_header_cache(hs_header_t *hdr);

void
hs_header_hash(hs_header_t *hdr, uint8_t *hash);

int
hs_header_verify_pow(const hs_header_t *hdr);

void
hs_header_print(hs_header_t *hdr, const char *prefix);
#endif
