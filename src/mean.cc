#if EDGEBITS >= 28
#include "tromp/mean_miner.hpp"
#endif
#include <unistd.h>
#include <stdbool.h>
#include "common.h"

int32_t
hs_mean_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
) {
#if EDGEBITS >= 28
  uint32_t nonce = options->nonce;
  uint32_t range = 1;
  uint32_t nthreads = 1;
  uint32_t ntrims = EDGEBITS > 30 ? 96 : 68;
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

  if (options->threads)
    nthreads = options->threads;

  if (options->trims)
    ntrims = options->trims & -2;

  mean_solver_ctx ctx(nthreads, ntrims, false, false);

  bool has_sol = false;

  *result = 0;
  *match = false;

  for (uint32_t r = 0; r < range; r++) {
    if (!options->running)
      break;

    ctx.setheadernonce((char *)header, header_len, nonce + r);

    uint32_t nsols = ctx.solve();

    for (uint32_t s = 0; s < nsols; s++) {
      uint32_t *sol = &ctx.sols[s * PROOFSIZE];

      int32_t rc = verify(sol, &ctx.trimmer->sip_keys);

      if (rc == POW_OK) {
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
    }
  }

  if (has_sol)
    return HS_SUCCESS;

  return HS_ENOSOLUTION;
#else
  return HS_ENOSUPPORT;
#endif
}
