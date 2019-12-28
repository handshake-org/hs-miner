#include <unistd.h>
#include <stdbool.h>
#include "common.h"

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
) {
  uint32_t nonce = options->nonce;
  uint32_t range = 1;
  size_t header_len = options->header_len;
  hs_header_t header[MAX_HEADER_SIZE];
  uint8_t hash[32];
  uint8_t chash[32];

  memset(hash, 0xff, 32);

  if (header_len < MIN_HEADER_SIZE || header_len > MAX_HEADER_SIZE)
    return HS_EBADARGS;

  memcpy(header, options->header, header_len);

  if (options->range)
    range = options->range;

  for (uint32_t r = 0; r < range; r++) {
    if (!options->running)
      break;

    hs_header_hash(header, chash);

    if (memcmp(chash, hash, 32) <= 0) {
      *result = nonce + r;
      memcpy(hash, chash, 32);
    }

    if (memcmp(chash, options->target, 32) <= 0) {
      *match = true;
      return HS_SUCCESS;
    }
  }

  return HS_EFAILURE;
}
