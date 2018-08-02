#include <unistd.h>
#include <stdbool.h>
#include "tromp/cuckoo.h"
#include "tromp/blake2.h"
#include "common.h"

int32_t
hs_verify(
  const uint8_t *hdr,
  size_t hdr_len,
  const uint8_t *solution,
  const uint8_t *target
) {
  int32_t rc = hs_verify_sol(hdr, hdr_len, solution);

  if (rc != POW_OK)
    return rc;

  if (!target)
    return rc;

  uint8_t hash[32];

  hs_pow_hash(solution, PROOFSIZE * 4, &hash[0]);

  if (memcmp(hash, target, 32) > 0)
    return POW_TOO_BIG;

  return POW_OK;
}

int32_t
hs_verify_sol(const uint8_t *hdr, size_t hdr_len, const uint8_t *solution) {
  siphash_keys keys;
  uint32_t sol[PROOFSIZE];

  setheader((const char *)hdr, hdr_len, &keys);

  for (int32_t i = 0; i < PROOFSIZE; i++)
    sol[i] = hs_read_u32(&solution[i * 4]);

  return verify(sol, &keys);
}
