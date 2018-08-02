#include "tromp/simple_miner.cpp"
#include <unistd.h>
#include <stdbool.h>
#include "common.h"

int32_t
hs_simple_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
) {
  uint32_t nonce = options->nonce;
  uint32_t range = 1;
  size_t header_len = options->header_len;
  uint8_t header[MAX_HEADER_SIZE];
  uint8_t hash[32];
  uint8_t chash[32];

  memset(hash, 0xff, 32);

  if (header_len < MIN_HEADER_SIZE || header_len > MAX_HEADER_SIZE)
    return HS_EBADARGS;

  memcpy(header, options->header, header_len);

  if (options->range)
    range = options->range;

  simple_cuckoo_ctx ctx((const char *)header, header_len, nonce, EASINESS);

  uint32_t sol[PROOFSIZE];
  bool has_sol = false;

  for (uint32_t r = 0; r < range; r++) {
    if (!options->running)
      break;

    ctx.setheadernonce((char *)header, header_len, nonce + r);

    if (!ctx.solve(sol))
      continue;

    hs_hash_solution(sol, chash);

    if (memcmp(chash, hash, 32) <= 0) {
      *result = nonce + r;
      for (int32_t i = 0; i < PROOFSIZE; i++)
        hs_write_u32(&solution[i * 4], sol[i]);
      memcpy(hash, chash, 32);
      has_sol = true;
    }

    if (memcmp(chash, options->target, 32) <= 0) {
      *match = true;
      return HS_SUCCESS;
    }
  }

  if (has_sol)
    return HS_SUCCESS;

  return HS_ENOSOLUTION;
}
