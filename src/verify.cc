#include <unistd.h>
#include <stdbool.h>
#include "common.h"
#include "header.h"

int32_t
hs_verify(
  hs_header_t *hdr,
  uint8_t *target
) {
  uint8_t hash[32];

  hs_header_hash(hdr, hash);

  if (memcmp(hash, target, 32) <= 0)
    return HS_SUCCESS;

  return HS_EFAILURE;
}
