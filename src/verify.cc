#include <stdbool.h>
#include "common.h"
#include "header.h"
#include "error.h"

int32_t
hs_verify(
  hs_header_t *hdr,
  uint8_t *target
) {
  return hs_header_verify_pow(hdr, target);
}
