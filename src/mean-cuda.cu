#if EDGEBITS >= 28
#include "tromp/mean_miner.cu"
#endif

#include <assert.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdint.h>
#include "common.h"

int32_t
hs_mean_cuda_run(
  hs_options_t *options,
  uint8_t *solution,
  uint32_t *result,
  bool *match
) {
#if EDGEBITS >= 28
  uint8_t header[MAX_HEADER_SIZE];
  size_t header_len = options->header_len;
  uint32_t nonce = options->nonce;
  uint32_t range = 1;
  uint32_t device = options->device;
  uint8_t hash[32];
  uint8_t chash[32];

  memset(hash, 0xff, 32);

  if (header_len < MIN_HEADER_SIZE || header_len > MAX_HEADER_SIZE)
    return HS_EBADARGS;

  memcpy(header, options->header, header_len);

  int32_t device_count = 0;
  cudaGetDeviceCount(&device_count);

  if (device_count < 0 || device >= device_count)
    return HS_ENODEVICE;

  cudaDeviceProp prop;
  cudaGetDeviceProperties(&prop, device);

  meancu_trimparams params;

  if (options->range)
    range = options->range;

  if (options->trims)
    params.ntrims = ((int32_t)options->trims) & -2;

  if (options->threads) {
    params.genUtpb *= options->threads;
    params.genV.stage1tpb *= options->threads;
    params.genV.stage2tpb *= options->threads;
    params.trim.stage1tpb *= options->threads;
    params.trim.stage2tpb *= options->threads;
    params.rename[0].stage1tpb *= options->threads;
    params.rename[0].stage2tpb *= options->threads;
    params.rename[1].stage1tpb *= options->threads;
    params.rename[1].stage2tpb *= options->threads;
    params.trim3tpb *= options->threads;
    params.rename3tpb *= options->threads;
    params.genUtpb /= 100;
    params.genV.stage1tpb /= 100;
    params.genV.stage2tpb /= 100;
    params.trim.stage1tpb /= 100;
    params.trim.stage2tpb /= 100;
    params.rename[0].stage1tpb /= 100;
    params.rename[0].stage2tpb /= 100;
    params.rename[1].stage1tpb /= 100;
    params.rename[1].stage2tpb /= 100;
    params.trim3tpb /= 100;
    params.rename3tpb /= 100;
  }

  if (prop.maxThreadsPerBlock <= params.genUtpb
      || prop.maxThreadsPerBlock <= params.genV.stage1tpb
      || prop.maxThreadsPerBlock <= params.genV.stage2tpb
      || prop.maxThreadsPerBlock <= params.trim.stage1tpb
      || prop.maxThreadsPerBlock <= params.trim.stage2tpb
      || prop.maxThreadsPerBlock <= params.rename[0].stage1tpb
      || prop.maxThreadsPerBlock <= params.rename[0].stage2tpb
      || prop.maxThreadsPerBlock <= params.rename[1].stage1tpb
      || prop.maxThreadsPerBlock <= params.rename[1].stage2tpb
      || prop.maxThreadsPerBlock <= params.trim3tpb
      || prop.maxThreadsPerBlock <= params.rename3tpb) {
    return HS_EBADPROPS;
  }

  cudaSetDevice(device);

  meancu_solver_ctx ctx(params);

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
