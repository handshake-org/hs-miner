#include <unistd.h>
#include <stdbool.h>
#include "tromp/cuckoo.h"
#include "tromp/blake2.h"
#include "common.h"

int32_t
hsk_verify(
  uint8_t *hdr,
  size_t hdr_len,
  uint8_t *solution,
  uint8_t *target
) {
  int32_t rc = hsk_verify_sol(hdr, hdr_len, solution);

  if (rc != POW_OK)
    return rc;

  if (!target)
    return rc;

  uint8_t hash[32];

  blake2b(
    (void *)hash,
    sizeof(hash),
    (const void *)solution,
    PROOFSIZE * 4,
    0,
    0
  );

  if (memcmp(hash, target, 32) > 0)
    return POW_TOO_BIG;

  return POW_OK;
}

int32_t
hsk_verify_sol(uint8_t *hdr, size_t hdr_len, uint8_t *solution) {
  siphash_keys keys;
  uint32_t sol[PROOFSIZE];

  setheader((const char *)hdr, hdr_len, &keys);

  for (int32_t i = 0; i < PROOFSIZE; i++)
    sol[i] = hsk_read_u32(&solution[i * 4]);

  return verify(sol, &keys);
}
