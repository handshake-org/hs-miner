#include <unistd.h>
#include <stdio.h>
#include <stdbool.h>
#include "common.h"
#include "header.h"
#include "error.h"
#include "utils.h"

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
) {
  uint32_t nonce = 0;
  uint32_t range = 1;
  size_t header_len = options->header_len;
  hs_header_t header[HEADER_SIZE];

  if (options->nonce)
    nonce = options->nonce;

  if (options->range)
    range = options->range;

  uint32_t max = nonce + range;

  if (header_len != HEADER_SIZE)
    return HS_EBADARGS;

  hs_header_decode(options->header, header_len, header);

  uint8_t hash[32];
  memset(hash, 0xff, 32);

  uint8_t target[32];
  memcpy(target, options->target, 32);

  // Cache padding
  uint8_t pad32[32];
  hs_header_padding(header, pad32, 32);

  // Compute share data
  uint8_t share[128];
  hs_header_share_encode(header, share);

  for (; nonce < max; nonce++) {
    if (!options->running)
      break;

    // Insert nonce into share
    memcpy(share, &nonce, 4);

    hs_header_share_pow(share, pad32, hash);

    if (memcmp(hash, target, 32) < 0) {
      *match = true;
      *result = nonce;
      return HS_SUCCESS;
    }
  }

  return HS_ENOSOLUTION;
}
