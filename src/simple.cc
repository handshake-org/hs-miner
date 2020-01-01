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

  if (header_len != HEADER_SIZE)
    return HS_EBADARGS;

  hs_header_decode(options->header, header_len, header);

  uint8_t hash[32];
  memset(hash, 0xff, 32);

  uint8_t target[32];
  memcpy(target, options->target, 32);

  uint64_t extra_nonce = hs_nonce();

  // Randomize the extra nonce for
  // each set of CPU jobs.
  memset(header->extra_nonce, extra_nonce, sizeof(extra_nonce));

  for (uint32_t r = 0; r < range; r++) {
    if (!options->running)
      break;

    header->nonce = nonce + r;

    hs_header_pow(header, hash);

    if (memcmp(hash, target, 32) < 0) {
      *match = true;
      *result = header->nonce;
      return HS_SUCCESS;
    }
  }

  return HS_ENOSOLUTION;
}

