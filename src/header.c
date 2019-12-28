#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

#include "bio.h"
#include "tromp/blake2.h"
#include "error.h"
#include "header.h"
#include "sha3.h"
#include "error.h"
#include "utils.h"

void
hs_header_init(hs_header_t *hdr) {
  if (!hdr)
    return;

  // Preheader.
  hdr->nonce = 0;
  hdr->time = 0;
  memset(hdr->prev_block, 0, 32);
  memset(hdr->name_root, 0, 32);

  // Subheader.
  memset(hdr->extra_nonce, 0, 24);
  memset(hdr->reserved_root, 0, 32);
  memset(hdr->witness_root, 0, 32);
  memset(hdr->merkle_root, 0, 32);
  hdr->version = 0;
  hdr->bits = 0;

  // Mask.
  memset(hdr->mask, 0, 32);

  hdr->cache = false;
  memset(hdr->hash, 0, 32);
  hdr->height = 0;
  memset(hdr->work, 0, 32);

  hdr->next = NULL;
}

hs_header_t *
hs_header_alloc(void) {
  hs_header_t *hdr = malloc(sizeof(hs_header_t));
  hs_header_init(hdr);
  return hdr;
}

bool
hs_header_read(uint8_t **data, size_t *data_len, hs_header_t *hdr) {
  if (!read_u32(data, data_len, &hdr->nonce))
    return false;

  if (!read_u64(data, data_len, &hdr->time))
    return false;

  if (!read_bytes(data, data_len, hdr->prev_block, 32))
    return false;

  if (!read_bytes(data, data_len, hdr->name_root, 32))
    return false;

  if (!read_bytes(data, data_len, hdr->extra_nonce, 24))
    return false;

  if (!read_bytes(data, data_len, hdr->reserved_root, 32))
    return false;

  if (!read_bytes(data, data_len, hdr->witness_root, 32))
    return false;

  if (!read_bytes(data, data_len, hdr->merkle_root, 32))
    return false;

  if (!read_u32(data, data_len, &hdr->version))
    return false;

  if (!read_u32(data, data_len, &hdr->bits))
    return false;

  if (!read_bytes(data, data_len, hdr->mask, 32))
    return false;

  return true;
}

bool
hs_header_decode(const uint8_t *data, size_t data_len, hs_header_t *hdr) {
  return hs_header_read((uint8_t **)&data, &data_len, hdr);
}

int
hs_header_write(const hs_header_t *hdr, uint8_t **data) {
  int s = 0;
  s += write_u32(data, hdr->nonce);
  s += write_u64(data, hdr->time);
  s += write_bytes(data, hdr->prev_block, 32);
  s += write_bytes(data, hdr->name_root, 32);
  s += write_bytes(data, hdr->extra_nonce, 24);
  s += write_bytes(data, hdr->reserved_root, 32);
  s += write_bytes(data, hdr->witness_root, 32);
  s += write_bytes(data, hdr->merkle_root, 32);
  s += write_u32(data, hdr->version);
  s += write_u32(data, hdr->bits);
  s += write_bytes(data, hdr->mask, 32);
  return s;
}

int
hs_header_size(const hs_header_t *hdr) {
  return hs_header_write(hdr, NULL);
}

int
hs_header_encode(const hs_header_t *hdr, uint8_t *data) {
  return hs_header_write(hdr, &data);
}

int
hs_header_pre_write(const hs_header_t *hdr, uint8_t **data) {
  int s = 0;
  uint8_t pad[20];
  uint8_t commit_hash[32];

  hs_header_padding(hdr, pad, 20);
  hs_header_commit_hash(hdr, commit_hash);

  s += write_u32(data, hdr->nonce);
  s += write_u64(data, hdr->time);
  s += write_bytes(data, pad, 20);
  s += write_bytes(data, hdr->prev_block, 32);
  s += write_bytes(data, hdr->name_root, 32);
  s += write_bytes(data, commit_hash, 32);
  return s;
}

int
hs_header_pre_size(const hs_header_t *hdr) {
  return hs_header_pre_write(hdr, NULL);
}

int
hs_header_pre_encode(const hs_header_t *hdr, uint8_t *data) {
  return hs_header_pre_write(hdr, &data);
}

int
hs_header_sub_write(const hs_header_t *hdr, uint8_t **data) {
  int s = 0;
  s += write_bytes(data, hdr->extra_nonce, 24);
  s += write_bytes(data, hdr->reserved_root, 32);
  s += write_bytes(data, hdr->witness_root, 32);
  s += write_bytes(data, hdr->merkle_root, 32);
  s += write_u32(data, hdr->version);
  s += write_u32(data, hdr->bits);
  return s;
}

int
hs_header_sub_size(const hs_header_t *hdr) {
  return hs_header_sub_write(hdr, NULL);
}

int
hs_header_sub_encode(const hs_header_t *hdr, uint8_t *data) {
  return hs_header_sub_write(hdr, &data);
}

void
hs_header_sub_hash(const hs_header_t *hdr, uint8_t *hash) {
  int size = hs_header_sub_size(hdr);
  uint8_t sub[size];
  hs_header_sub_encode(hdr, sub);

  blake2b_state ctx;
  assert(blake2b_init(&ctx, 32) == 0);
  blake2b_update(&ctx, sub, size);
  assert(blake2b_final(&ctx, hash, 32) == 0);
}

void
hs_header_mask_hash(const hs_header_t *hdr, uint8_t *hash) {
  blake2b_state ctx;
  assert(blake2b_init(&ctx, 32) == 0);
  blake2b_update(&ctx, hdr->prev_block, 32);
  blake2b_update(&ctx, hdr->mask, 32);
  assert(blake2b_final(&ctx, hash, 32) == 0);
}

void
hs_header_commit_hash(const hs_header_t *hdr, uint8_t *hash) {
  uint8_t sub_hash[32];
  uint8_t mask_hash[32];

  hs_header_sub_hash(hdr, sub_hash);
  hs_header_mask_hash(hdr, mask_hash);

  blake2b_state ctx;
  assert(blake2b_init(&ctx, 32) == 0);
  blake2b_update(&ctx, sub_hash, 32);
  blake2b_update(&ctx, mask_hash, 32);
  assert(blake2b_final(&ctx, hash, 32) == 0);
}

void
hs_header_padding(const hs_header_t *hdr, uint8_t *pad, size_t size) {
  assert(hdr && pad);

  size_t i;

  for (i = 0; i < size; i++)
    pad[i] = hdr->prev_block[i % 32] ^ hdr->name_root[i % 32];
}

bool
hs_header_equal(hs_header_t *a, hs_header_t *b) {
  return memcmp(hs_header_cache(a), hs_header_cache(b), 32) == 0;
}

const uint8_t *
hs_header_cache(hs_header_t *hdr) {
  if (hdr->cache)
    return hdr->hash;

  int size = hs_header_pre_size(hdr);
  uint8_t pre[size];
  uint8_t pad8[8];
  uint8_t pad32[32];
  uint8_t left[64];
  uint8_t right[32];

  // Generate pads.
  hs_header_padding(hdr, pad8, 8);
  hs_header_padding(hdr, pad32, 32);

  // Generate left.
  hs_header_pre_encode(hdr, pre);
  blake2b_state ctx;
  assert(blake2b_init(&ctx, 64) == 0);
  blake2b_update(&ctx, pre, size);
  assert(blake2b_final(&ctx, left, 64) == 0);

  // Generate right.
  hs_sha3_ctx s_ctx;
  hs_sha3_256_init(&s_ctx);
  hs_sha3_update(&s_ctx, pre, size);
  hs_sha3_update(&s_ctx, pad8, 8);
  hs_sha3_final(&s_ctx, right);

  // Generate hash.
  blake2b_state b_ctx;
  assert(blake2b_init(&b_ctx, 32) == 0);
  blake2b_update(&b_ctx, left, 64);
  blake2b_update(&b_ctx, pad32, 32);
  blake2b_update(&b_ctx, right, 32);
  assert(blake2b_final(&b_ctx, hdr->hash, 32) == 0);

  // XOR PoW hash with arbitrary bytes.
  // This can be used by mining pools to
  // mitigate block witholding attacks.
  int i;
  for (i = 0; i < 32; i++)
    hdr->hash[i] ^= hdr->mask[i];

  hdr->cache = true;

  return hdr->hash;
}

void
hs_header_hash(hs_header_t *hdr, uint8_t *hash) {
  memcpy(hash, hs_header_cache(hdr), 32);
}

int
hs_header_verify_pow(const hs_header_t *hdr) {
  uint8_t target[32];

  if (!hs_pow_to_target(hdr->bits, target))
    return HS_ENEGTARGET;

  uint8_t hash[32];

  hs_header_hash((hs_header_t *)hdr, hash);

  if (memcmp(hash, target, 32) > 0)
    return HS_EHIGHHASH;

  return HS_SUCCESS;
}

void
hs_header_print(hs_header_t *hdr, const char *prefix) {
  assert(hdr);

  char hash[65];
  char work[65];
  char prev_block[65];
  char name_root[65];
  char extra_nonce[49];
  char reserved_root[65];
  char witness_root[65];
  char merkle_root[65];
  char mask[65];

  assert(hs_hex_encode(hs_header_cache(hdr), 32, hash));
  assert(hs_hex_encode(hdr->work, 32, work));
  assert(hs_hex_encode(hdr->prev_block, 32, prev_block));
  assert(hs_hex_encode(hdr->name_root, 32, name_root));
  assert(hs_hex_encode(hdr->extra_nonce, 24, extra_nonce));
  assert(hs_hex_encode(hdr->reserved_root, 32, reserved_root));
  assert(hs_hex_encode(hdr->witness_root, 32, witness_root));
  assert(hs_hex_encode(hdr->merkle_root, 32, merkle_root));
  assert(hs_hex_encode(hdr->mask, 32, mask));

  printf("%sheader\n", prefix);
  printf("%s  hash=%s\n", prefix, hash);
  printf("%s  height=%u\n", prefix, hdr->height);
  printf("%s  work=%s\n", prefix, work);
  printf("%s  nonce=%u\n", prefix, hdr->nonce);
  printf("%s  time=%u\n", prefix, (uint32_t)hdr->time);
  printf("%s  prev_block=%s\n", prefix, prev_block);
  printf("%s  name_root=%s\n", prefix, name_root);
  printf("%s  extra_nonce=%s\n", prefix, extra_nonce);
  printf("%s  reserved_root=%s\n", prefix, reserved_root);
  printf("%s  witness_root=%s\n", prefix, witness_root);
  printf("%s  merkle_root=%s\n", prefix, merkle_root);
  printf("%s  version=%u\n", prefix, hdr->version);
  printf("%s  bits=%u\n", prefix, hdr->bits);
  printf("%s  mask=%s\n", prefix, mask);
}