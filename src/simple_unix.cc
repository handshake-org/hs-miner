#ifndef _WIN32
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
  uint8_t thread;
} hs_thread_args_t;

void *
hs_simple_thread(void *ptr) {
  hs_thread_args_t *args = (hs_thread_args_t *)ptr;
  hs_options_t *options = args->options;
  uint32_t *result = args->result;
  bool *match = args->match;
  uint8_t thread = args->thread;

  uint32_t nonce = 0;
  uint32_t range = 1;
  size_t header_len = options->header_len;
  hs_header_t header[HEADER_SIZE];

  if (options->nonce)
    nonce = options->nonce;

  if (options->range)
    range = options->range;

  // Split up the range into threads and start
  // this thread's nonce from a unique point in the range.
  uint32_t sub_range = range / options->threads;
  nonce += sub_range * thread;
  uint32_t max = nonce + sub_range;

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
      return (void *)HS_EABORT;

    // Insert nonce into share
    memcpy(share, &nonce, 4);

    hs_header_share_pow(share, pad32, hash);

    if (memcmp(hash, target, 32) <= 0) {
      // WINNER!
      options->running = false;

      *match = true;
      *result = nonce;
      return (void *)HS_SUCCESS;
    }
  }

  return (void *)HS_ENOSOLUTION;
}

// Return code for hs_simple_thread() threads must be in scope
// even after hs_simple_run returns or it'll segfault.
int32_t rc;

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  uint8_t *extra_nonce,
  bool *match
) {
  uint8_t NUM_THREADS = options->threads;
  pthread_t threads[NUM_THREADS];

  // Array of args structs for each thread
  hs_thread_args_t args[NUM_THREADS];

  for(uint8_t i = 0; i < NUM_THREADS; i++) {
    // Create new args object in memory for each thread so we can add
    // thread IDs to it and return different nonces.
    args[i].options = options;
    args[i].result = result;
    args[i].match = match;
    args[i].thread = i;

    int err = pthread_create(&threads[i], NULL, hs_simple_thread, &args[i]);
    if (err != 0) {
      exit(err);
    }
  }

  int32_t final_rc = HS_MAXERROR;
  for(uint8_t i = 0; i < NUM_THREADS; i++) {
    pthread_join(threads[i], (void **)&rc);
    if (rc < final_rc)
      final_rc = 0;
  }
  return final_rc;
}
#endif
