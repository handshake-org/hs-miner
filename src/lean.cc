#if EDGEBITS >= 5
#include "tromp/lean_miner.hpp"
#endif
#include <unistd.h>
#include <stdbool.h>
#include "common.h"

int32_t
hs_lean_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
) {
#if EDGEBITS >= 5
  uint32_t nonce = options->nonce;
  uint32_t range = 1;
  uint32_t nthreads = 1;
  uint32_t ntrims = 1;
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
    ntrims = options->trims;

  ntrims += (PART_BITS + 3) * (PART_BITS + 4) / 2;

  lean_thread_ctx *threads =
    (lean_thread_ctx *)calloc(nthreads, sizeof(lean_thread_ctx));

  if (!threads)
    return HS_ENOMEM;

  lean_cuckoo_ctx ctx(nthreads, ntrims, 8);

  int32_t rc = HS_SUCCESS;
  bool has_sol = false;

  *result = 0;
  *match = false;

  for (uint32_t r = 0; r < range; r++) {
    if (!options->running)
      break;

    ctx.setheadernonce((char *)header, header_len, nonce + r);

    for (uint32_t i = 0; i < nthreads; i++) {
      threads[i].id = i;
      threads[i].ctx = &ctx;
      threads[i].running = &options->running;

      int32_t err = pthread_create(
        &threads[i].thread,
        NULL,
        worker,
        (void *)&threads[i]
      );

      if (err != 0) {
        rc = HS_EFAILURE;
        goto done;
      }
    }

    for (uint32_t i = 0; i < nthreads; i++) {
      int32_t err = pthread_join(threads[i].thread, NULL);

      if (err != 0) {
        rc = HS_EFAILURE;
        goto done;
      }
    }

    for (uint32_t s = 0; s < ctx.nsols; s++) {
      uint32_t *sol = ctx.sols[s];

      for (int32_t i = 0; i < PROOFSIZE; i++) {
        if (sol[i] >= EASINESS) {
          sol = NULL;
          break;
        }
      }

      if (!sol)
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
        goto done;
      }
    }
  }

  if (!has_sol)
    rc = HS_ENOSOLUTION;

done:
  free(threads);

  return rc;
#else
  return HS_ENOSUPPORT;
#endif
}
