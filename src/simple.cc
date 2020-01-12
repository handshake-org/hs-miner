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
  uint8_t thread;
} hs_thread_args_t;

void
*hs_simple_thread(void *ptr) {
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

    // printf("Thread: %u Nonce: %zu Hash: %02x%02x%02x%02x\n",
    //   thread, nonce, hash[0], hash[1], hash[2], hash[3]);

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

int32_t
hs_simple_run(
  hs_options_t *options,
  uint32_t *result,
  bool *match
) {
  uint8_t NUM_THREADS = options->threads;
  pthread_t threads[NUM_THREADS];

  // Array of args structs for each thread
  hs_thread_args_t *thread_args[NUM_THREADS];

  for(uint8_t i = 0; i < NUM_THREADS; i++) {
    // Create new args object in memory for each thread so we can add
    // thread IDs to it and return different nonces.
    thread_args[i] = (hs_thread_args_t *)malloc(sizeof(hs_thread_args_t));
    thread_args[i]->options = options;
    thread_args[i]->result = result;
    thread_args[i]->match = match;
    thread_args[i]->thread = i;

    int err =
      pthread_create(&threads[i], NULL, hs_simple_thread, thread_args[i]);
    if (err != 0) {
      printf("Error creating thread: %u\n", err);
      exit(err);
    }
  }

  for(uint8_t i = 0; i < NUM_THREADS; i++) {
    int32_t *rc;
    pthread_join(threads[i], (void **)&rc);
    if (rc != 0)
      printf("Thread %u returned error code: %zu\n", i, rc);
  }
  return HS_SUCCESS;
}
