/*!
 * cuda.cuh - CUDA Mining header for hs-mminer
 * Copyright (c) 2019-2020, The Handshake Developers (MIT License).
 * https://github.com/handshake-org/hs-miner
 */

#pragma once

__device__ inline char
cuda_to_char(uint8_t n) {
  if (n >= 0x00 && n <= 0x09)
    return n + '0';

  if (n >= 0x0a && n <= 0x0f)
    return (n - 0x0a) + 'a';

  return -1;
}

__device__ bool
cuda_hs_hex_encode(const uint8_t *data, size_t data_len, char *str) {
  if (data == NULL && data_len != 0)
    return false;

  if (str == NULL)
    return false;

  size_t size = data_len << 1;

  int i;
  int p = 0;

  for (i = 0; i < size; i++) {
    char ch;

    if (i & 1) {
      ch = cuda_to_char(data[p] & 15);
      p += 1;
    } else {
      ch = cuda_to_char(data[p] >> 4);
    }

    if (ch == -1)
      return false;

    str[i] = ch;
  }

  str[i] = '\0';

  return true;
}

int32_t hs_cuda_run(hs_options_t *options, uint32_t *result, bool *match);
