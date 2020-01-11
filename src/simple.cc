#include <unistd.h>
#include <stdio.h>
#include <stdbool.h>
#include <pthread.h>
#include "common.h"
#include "header.h"
#include "error.h"
#include "utils.h"

typedef struct hs_thread_args_s {
  hs_options_t *options;
  uint32_t *result;
  bool *match;
} hs_thread_args_t;

void
*hs_simple_thread(void *ptr) {
  hs_thread_args_t *args = (hs_thread_args_t *)ptr;
  hs_options_t *options = args->options;
  uint32_t *result = args->result;
  bool *match = args->match;

  uint32_t nonce = 0;
  uint32_t range = 1;
  size_t header_len = options->header_len;
  hs_header_t header[HEADER_SIZE];

  if (options->nonce)
    nonce = options->nonce;

  if (options->range)
    range = options->range;

  uint32_t max = nonce + range;

  if (header_len != HEADER_SIZE)
    return (void *)HS_EBADARGS;

  hs_header_decode(options->header, header_len, header);

  uint8_t hash[32];
  memset(hash, 0xff, 32);

  uint8_t target[32];
  memcpy(target, options->target, 32);

  // Cache padding
  uint8_t pad32[32];
  hs_header_padding(header, pad32, 32);

  // Compute share data
  uint8_t share[128];
  hs_header_share_encode(header, share);

  for (; nonce < max; nonce++) {
    if (!options->running)
      break;
    // printf("Thread: %u Nonce: %zu\n", pthread_self(), nonce);

    // Insert nonce into share
    memcpy(share, &nonce, 4);

    hs_header_share_pow(share, pad32, hash);

    if (memcmp(hash, target, 32) <= 0) {
      *match = true;
      *result = nonce;
      return (void *)HS_SUCCESS;
    }
  }

  return (void *)HS_ENOSOLUTION;
}

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
) {
  hs_thread_args_t args;
  args.options = options;
  args.result = result;
  args.match = match;

  uint8_t NUM_THREADS = options->threads;
  pthread_t threads[NUM_THREADS];

  for(uint8_t i = 0; i < NUM_THREADS; i++) {
    // printf("Creating thread: %u\n", i);
    int err = pthread_create(&threads[i], NULL, hs_simple_thread, &args);
    if (err != 0) {
      printf("Error creating thread: %u\n", err);
      exit(err);
    }
  }

  for(uint8_t i = 0; i < NUM_THREADS; i++) {
    int32_t *rc;
    pthread_join(threads[i], (void **)&rc);
    // printf("Return code from thread %u: %zu\n", i, rc);
  }
  return HS_SUCCESS;
}
