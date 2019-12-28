#include <unistd.h>
#include <stdio.h>
#include <stdbool.h>
#include "common.h"

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
) {
  uint32_t nonce = options->nonce;
  uint32_t range = options->range;;
  size_t header_len = options->header_len;
  hs_header_t header[MAX_HEADER_SIZE];
  uint8_t hash[32];

  memset(hash, 0xff, 32);

  if (header_len < MIN_HEADER_SIZE || header_len > MAX_HEADER_SIZE)
    return HS_EBADARGS;

  memcpy(header, options->header, header_len);

  if (options->range)
    range = options->range;

  for (uint32_t r = 0; r < range; r++) {
    if (!options->running)
      break;

    header->nonce = nonce + r;
    header->cache = false;

    //printf("nonce: %d\n", header->nonce);

    hs_header_hash(header, hash);

    //for (uint i=0; i < sizeof(hash); i++)
    //printf("%02x", hash[i]);
    //printf("\n");

    if (memcmp(hash, options->target, 32) <= 0) {
      *result = header->nonce;
      *match = true;
      return HS_SUCCESS;
    }
  }

  return HS_ENOSOLUTION;
}
