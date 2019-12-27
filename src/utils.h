#ifndef _HS_UTILS_H
#define _HS_UTILS_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

int64_t
hs_now(void);

void
hs_date(
  int64_t now,
  uint32_t *year,
  uint32_t *month,
  uint32_t *day,
  uint32_t *hour,
  uint32_t *min,
  uint32_t *sec
);

void
hs_ymdh(uint32_t *year, uint32_t *month, uint32_t *day, uint32_t *hour);

void
hs_ymd(uint32_t *year, uint32_t *month, uint32_t *day);

uint32_t
hs_random(void);

uint64_t
hs_nonce(void);

size_t
hs_hex_encode_size(size_t data_len);

char *
hs_hex_encode(const uint8_t *data, size_t data_len, char *str);

const char *
hs_hex_encode32(const uint8_t *data);

const char *
hs_hex_encode20(const uint8_t *data);

size_t
hs_hex_decode_size(const char *str);

bool
hs_hex_decode(const char *str, uint8_t *data);

void
hs_to_lower(char *name);
#endif
