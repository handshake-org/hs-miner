typedef unsigned char BYTE;
typedef unsigned int  WORD;
typedef unsigned long LONG;

inline int
opencl_memcmp(const void *a, const void *b, size_t n) {
  const BYTE *ua = (const BYTE *) a;
  const BYTE *ub = (const BYTE *) b;

  while (n--) {
    if (*ua != *ub) {
      return (*ua < *ub) ? -1 : 1;
    }
    ua++;
    ub++;
  }
  return 0;
}

inline int
opencl_memcpy(void *a, const void *b, size_t n) {
  BYTE *ua = (BYTE *) a;
  const BYTE *ub = (BYTE *) b;

  while (n--)
    *(ua++) = *(ub++);

  return 0;
}

inline int
opencl_memset(void *a, int c, size_t n) {
  BYTE *dst = (BYTE *) a;
  while(n--)
    *(dst++) = (BYTE) c;

  return 0;
}

#define KECCAK_ROUND 24
#define KECCAK_STATE_SIZE 25
#define KECCAK_Q_SIZE 192

constant LONG CUDA_KECCAK_CONSTS[24] = {
  0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
  0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
  0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
  0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
  0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
  0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
  0x8000000000008080, 0x0000000080000001, 0x8000000080008008
};

typedef struct {
  BYTE sha3_flag;
  WORD digestbitlen;
  LONG rate_bits;
  LONG rate_bytes;
  LONG absorb_round;

  long state[KECCAK_STATE_SIZE];
  BYTE q[KECCAK_Q_SIZE];

  LONG bits_in_queue;
} opencl_keccak_ctx_t;

typedef opencl_keccak_ctx_t OPENCL_KECCAK_CTX;

inline LONG
opencl_keccak_leuint64(void *in) {
  LONG a;
  opencl_memcpy(&a, in, 8);
  return a;
}

inline long
opencl_keccak_MIN(long a, long b) {
  if (a > b) return b;
  return a;
}

inline LONG
opencl_keccak_UMIN(ulong a, ulong b) {
  if (a > b) return b;
  return a;
}

inline void
opencl_keccak_extract(OPENCL_KECCAK_CTX *ctx) {
  LONG len = ctx->rate_bits >> 6;
  long a;
  int s = sizeof(LONG);

  for (int i = 0;i < len;i++) {
    a = opencl_keccak_leuint64((long *)&ctx->state[i]);
    opencl_memcpy(ctx->q + (i * s), &a, s);
  }
}

inline LONG
opencl_keccak_ROTL64(ulong a, ulong b) {
  return (a << b) | (a >> (64 - b));
}

inline void
opencl_keccak_permutations(OPENCL_KECCAK_CTX *ctx) {
  long *A = ctx->state;

  long *a00 = A, *a01 = A + 1, *a02 = A + 2, *a03 = A + 3, *a04 = A + 4;
  long *a05 = A + 5, *a06 = A + 6, *a07 = A + 7, *a08 = A + 8, *a09 = A + 9;
  long *a10 = A + 10, *a11 = A + 11, *a12 = A + 12, *a13 = A + 13, *a14 = A + 14;
  long *a15 = A + 15, *a16 = A + 16, *a17 = A + 17, *a18 = A + 18, *a19 = A + 19;
  long *a20 = A + 20, *a21 = A + 21, *a22 = A + 22, *a23 = A + 23, *a24 = A + 24;

  for (int i = 0; i < KECCAK_ROUND; i++) {
    /* Theta */
    long c0 = *a00 ^ *a05 ^ *a10 ^ *a15 ^ *a20;
    long c1 = *a01 ^ *a06 ^ *a11 ^ *a16 ^ *a21;
    long c2 = *a02 ^ *a07 ^ *a12 ^ *a17 ^ *a22;
    long c3 = *a03 ^ *a08 ^ *a13 ^ *a18 ^ *a23;
    long c4 = *a04 ^ *a09 ^ *a14 ^ *a19 ^ *a24;

    long d1 = opencl_keccak_ROTL64(c1, 1) ^ c4;
    long d2 = opencl_keccak_ROTL64(c2, 1) ^ c0;
    long d3 = opencl_keccak_ROTL64(c3, 1) ^ c1;
    long d4 = opencl_keccak_ROTL64(c4, 1) ^ c2;
    long d0 = opencl_keccak_ROTL64(c0, 1) ^ c3;

    *a00 ^= d1;
    *a05 ^= d1;
    *a10 ^= d1;
    *a15 ^= d1;
    *a20 ^= d1;
    *a01 ^= d2;
    *a06 ^= d2;
    *a11 ^= d2;
    *a16 ^= d2;
    *a21 ^= d2;
    *a02 ^= d3;
    *a07 ^= d3;
    *a12 ^= d3;
    *a17 ^= d3;
    *a22 ^= d3;
    *a03 ^= d4;
    *a08 ^= d4;
    *a13 ^= d4;
    *a18 ^= d4;
    *a23 ^= d4;
    *a04 ^= d0;
    *a09 ^= d0;
    *a14 ^= d0;
    *a19 ^= d0;
    *a24 ^= d0;

    /* Rho pi */
    c1 = opencl_keccak_ROTL64(*a01, 1);
    *a01 = opencl_keccak_ROTL64(*a06, 44);
    *a06 = opencl_keccak_ROTL64(*a09, 20);
    *a09 = opencl_keccak_ROTL64(*a22, 61);
    *a22 = opencl_keccak_ROTL64(*a14, 39);
    *a14 = opencl_keccak_ROTL64(*a20, 18);
    *a20 = opencl_keccak_ROTL64(*a02, 62);
    *a02 = opencl_keccak_ROTL64(*a12, 43);
    *a12 = opencl_keccak_ROTL64(*a13, 25);
    *a13 = opencl_keccak_ROTL64(*a19, 8);
    *a19 = opencl_keccak_ROTL64(*a23, 56);
    *a23 = opencl_keccak_ROTL64(*a15, 41);
    *a15 = opencl_keccak_ROTL64(*a04, 27);
    *a04 = opencl_keccak_ROTL64(*a24, 14);
    *a24 = opencl_keccak_ROTL64(*a21, 2);
    *a21 = opencl_keccak_ROTL64(*a08, 55);
    *a08 = opencl_keccak_ROTL64(*a16, 45);
    *a16 = opencl_keccak_ROTL64(*a05, 36);
    *a05 = opencl_keccak_ROTL64(*a03, 28);
    *a03 = opencl_keccak_ROTL64(*a18, 21);
    *a18 = opencl_keccak_ROTL64(*a17, 15);
    *a17 = opencl_keccak_ROTL64(*a11, 10);
    *a11 = opencl_keccak_ROTL64(*a07, 6);
    *a07 = opencl_keccak_ROTL64(*a10, 3);
    *a10 = c1;

    /* Chi */
    c0 = *a00 ^ (~*a01 & *a02);
    c1 = *a01 ^ (~*a02 & *a03);
    *a02 ^= ~*a03 & *a04;
    *a03 ^= ~*a04 & *a00;
    *a04 ^= ~*a00 & *a01;
    *a00 = c0;
    *a01 = c1;

    c0 = *a05 ^ (~*a06 & *a07);
    c1 = *a06 ^ (~*a07 & *a08);
    *a07 ^= ~*a08 & *a09;
    *a08 ^= ~*a09 & *a05;
    *a09 ^= ~*a05 & *a06;
    *a05 = c0;
    *a06 = c1;

    c0 = *a10 ^ (~*a11 & *a12);
    c1 = *a11 ^ (~*a12 & *a13);
    *a12 ^= ~*a13 & *a14;
    *a13 ^= ~*a14 & *a10;
    *a14 ^= ~*a10 & *a11;
    *a10 = c0;
    *a11 = c1;

    c0 = *a15 ^ (~*a16 & *a17);
    c1 = *a16 ^ (~*a17 & *a18);
    *a17 ^= ~*a18 & *a19;
    *a18 ^= ~*a19 & *a15;
    *a19 ^= ~*a15 & *a16;
    *a15 = c0;
    *a16 = c1;

    c0 = *a20 ^ (~*a21 & *a22);
    c1 = *a21 ^ (~*a22 & *a23);
    *a22 ^= ~*a23 & *a24;
    *a23 ^= ~*a24 & *a20;
    *a24 ^= ~*a20 & *a21;
    *a20 = c0;
    *a21 = c1;

    /* Iota */
    *a00 ^= CUDA_KECCAK_CONSTS[i];
  }
}

inline void
opencl_keccak_absorb(OPENCL_KECCAK_CTX *ctx, BYTE *in) {
  LONG offset = 0;
  for (LONG i = 0; i < ctx->absorb_round; ++i) {
    ctx->state[i] ^= opencl_keccak_leuint64(in + offset);
    offset += 8;
  }

  opencl_keccak_permutations(ctx);
}

inline void
opencl_keccak_pad(OPENCL_KECCAK_CTX *ctx) {
  ctx->q[ctx->bits_in_queue >> 3] |= (1L << (ctx->bits_in_queue & 7));

  if (++(ctx->bits_in_queue) == ctx->rate_bits) {
    opencl_keccak_absorb(ctx, ctx->q);
    ctx->bits_in_queue = 0;
  }

  LONG full = ctx->bits_in_queue >> 6;
  LONG partial = ctx->bits_in_queue & 63;

  LONG offset = 0;
  for (LONG i = 0; i < full; ++i) {
    ctx->state[i] ^= opencl_keccak_leuint64(ctx->q + offset);
    offset += 8;
  }

  if (partial > 0) {
    LONG mask = (1L << partial) - 1;
    ctx->state[full] ^= opencl_keccak_leuint64(ctx->q + offset) & mask;
  }

  ctx->state[(ctx->rate_bits - 1) >> 6] ^= 9223372036854775808UL; /* 1 << 63 */

  opencl_keccak_permutations(ctx);
  opencl_keccak_extract(ctx);

  ctx->bits_in_queue = ctx->rate_bits;
}

/*
 * digestbitlen must be 128 224 256 288 384 512
 */
inline void
opencl_keccak_init(OPENCL_KECCAK_CTX *ctx, WORD digestbitlen) {
  opencl_memset(ctx, 0, sizeof(OPENCL_KECCAK_CTX));
  ctx->sha3_flag = 1;
  ctx->digestbitlen = digestbitlen;
  ctx->rate_bits = 1600 - ((ctx->digestbitlen) << 1);
  ctx->rate_bytes = ctx->rate_bits >> 3;
  ctx->absorb_round = ctx->rate_bits >> 6;
  ctx->bits_in_queue = 0;
}

/*
 * digestbitlen must be 224 256 384 512
 */
inline void
opencl_keccak_sha3_init(OPENCL_KECCAK_CTX *ctx, WORD digestbitlen) {
  opencl_keccak_init(ctx, digestbitlen);
  ctx->sha3_flag = 1;
}

inline void
opencl_keccak_update(
  OPENCL_KECCAK_CTX *ctx,
  BYTE *in,
  LONG inlen
) {
  long bytes = ctx->bits_in_queue >> 3;
  long count = 0;

  while (count < inlen) {
    if (bytes == 0 && count <= ((long)(inlen - ctx->rate_bytes))) {
      do {
        opencl_keccak_absorb(ctx, in + count);
        count += ctx->rate_bytes;
      } while (count <= ((long)(inlen - ctx->rate_bytes)));
    } else {
      long partial = opencl_keccak_MIN(ctx->rate_bytes - bytes, inlen - count);
      opencl_memcpy(ctx->q + bytes, in + count, partial);

      bytes += partial;
      count += partial;

      if (bytes == ctx->rate_bytes) {
        opencl_keccak_absorb(ctx, ctx->q);
        bytes = 0;
      }
    }
  }
  ctx->bits_in_queue = bytes << 3;
}

inline void
opencl_keccak_final(OPENCL_KECCAK_CTX *ctx, BYTE *out) {
  if (ctx->sha3_flag) {
    int mask = (1 << 2) - 1;
    ctx->q[ctx->bits_in_queue >> 3] = (uchar)(0x02 & mask);
    ctx->bits_in_queue += 2;
  }

  opencl_keccak_pad(ctx);
  LONG i = 0;

  while (i < ctx->digestbitlen) {
    if (ctx->bits_in_queue == 0) {
      opencl_keccak_permutations(ctx);
      opencl_keccak_extract(ctx);
      ctx->bits_in_queue = ctx->rate_bits;
    }

    LONG partial = opencl_keccak_UMIN(ctx->bits_in_queue, ctx->digestbitlen - i);
    opencl_memcpy(out + (i >> 3), ctx->q + (ctx->rate_bytes - (ctx->bits_in_queue >> 3)), partial >> 3);
    ctx->bits_in_queue -= partial;
    i += partial;
  }
}

inline LONG
rotr64(const LONG a, const BYTE b) {
  return (a >> b) | (a << (64 - b));
}

__kernel void
pow_ng(
  __global LONG *g_header,
  __global WORD *g_nonce,
  __global bool *g_match
) {
  if (*g_match)
    return;

#define G(r,i,a,b,c,d)                     \
  a = a + b + m[blake2b_sigmas[r][2*i]];   \
  d = rotr64(d ^ a, 32);                   \
  c = c + d;                               \
  b = rotr64(b ^ c, 24);                   \
  a = a + b + m[blake2b_sigmas[r][2*i+1]]; \
  d = rotr64(d ^ a, 16);                   \
  c = c + d;                               \
  b = rotr64(b ^ c, 63);

#define ROUND(r)                \
  G(r,0,v[0],v[4],v[ 8],v[12]); \
  G(r,1,v[1],v[5],v[ 9],v[13]); \
  G(r,2,v[2],v[6],v[10],v[14]); \
  G(r,3,v[3],v[7],v[11],v[15]); \
  G(r,4,v[0],v[5],v[10],v[15]); \
  G(r,5,v[1],v[6],v[11],v[12]); \
  G(r,6,v[2],v[7],v[ 8],v[13]); \
  G(r,7,v[3],v[4],v[ 9],v[14]);

  const BYTE blake2b_sigmas[12][16] = {
    { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
    { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 },
    { 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 },
    { 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 },
    { 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 },
    { 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 },
    { 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 },
    { 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 },
    { 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 },
    { 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 },
    { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
    { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 }
  };

  LONG v[16] = {
    0x6a09e667f2bdc948UL, 0xbb67ae8584caa73bUL,
    0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
    0x510e527fade682d1UL, 0x9b05688c2b3e6c1fUL,
    0x1f83d9abfb41bd6bUL, 0x5be0cd19137e2179UL,
    0x6a09e667f3bcc908UL, 0xbb67ae8584caa73bUL,
    0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
    0x510e527fade68251UL, 0x9b05688c2b3e6c1fUL,
    0xe07c265404be4294UL, 0x5be0cd19137e2179UL
  };

  LONG m[16] = {
    g_header[ 0], g_header[ 1],
    g_header[ 2], g_header[ 3],
    g_header[ 4], g_header[ 5],
    g_header[ 6], g_header[ 7],
    g_header[ 8], g_header[ 9],
    g_header[10], g_header[11],
    g_header[12], g_header[13],
    g_header[14], g_header[15]
  };

  WORD nonce = get_global_id(0);
  opencl_memcpy(m, &nonce, 4);

  /**
   * Generate the left hash by calculating
   * the blake2b-512 hash of the preheader
   * and commit hash.
   */

  ROUND( 0 );
  ROUND( 1 );
  ROUND( 2 );
  ROUND( 3 );
  ROUND( 4 );
  ROUND( 5 );
  ROUND( 6 );
  ROUND( 7 );
  ROUND( 8 );
  ROUND( 9 );
  ROUND( 10 );
  ROUND( 11 );

  LONG l[8] = {
    0x6a09e667f2bdc948UL ^ v[0] ^ v[ 8],
    0xbb67ae8584caa73bUL ^ v[1] ^ v[ 9],
    0x3c6ef372fe94f82bUL ^ v[2] ^ v[10],
    0xa54ff53a5f1d36f1UL ^ v[3] ^ v[11],
    0x510e527fade682d1UL ^ v[4] ^ v[12],
    0x9b05688c2b3e6c1fUL ^ v[5] ^ v[13],
    0x1f83d9abfb41bd6bUL ^ v[6] ^ v[14],
    0x5be0cd19137e2179UL ^ v[7] ^ v[15]
  };

  /**
   * Generate the right hash by calculating
   * the sha3-256 hash of the preheader,
   * commit hash, and 8 bytes of padding.
   */

  LONG r[4];
  LONG p[4] = {g_header[16], g_header[17], g_header[18], g_header[19]};

  OPENCL_KECCAK_CTX kctx;
  opencl_keccak_init(&kctx, 256);
  opencl_keccak_update(&kctx, m, 128);
  opencl_keccak_update(&kctx, p, 8);
  opencl_keccak_final(&kctx, r);

  /**
   * Generate share hash by calculating
   * the blake2b-256 hash of the the left,
   * 32 bytes of padding, and the right.
   */

  m[ 0] = l[0];
  m[ 1] = l[1];
  m[ 2] = l[2];
  m[ 3] = l[3],
  m[ 4] = l[4];
  m[ 5] = l[5];
  m[ 6] = l[6];
  m[ 7] = l[7];
  m[ 8] = p[0];
  m[ 9] = p[1];
  m[10] = p[2];
  m[11] = p[3];
  m[12] = r[0];
  m[13] = r[1];
  m[14] = r[2];
  m[15] = r[3];

  v[ 0] = 0x6a09e667f2bdc928UL;
  v[ 1] = 0xbb67ae8584caa73bUL;
  v[ 2] = 0x3c6ef372fe94f82bUL;
  v[ 3] = 0xa54ff53a5f1d36f1UL;
  v[ 4] = 0x510e527fade682d1UL;
  v[ 5] = 0x9b05688c2b3e6c1fUL;
  v[ 6] = 0x1f83d9abfb41bd6bUL;
  v[ 7] = 0x5be0cd19137e2179UL;
  v[ 8] = 0x6a09e667f3bcc908UL;
  v[ 9] = 0xbb67ae8584caa73bUL;
  v[10] = 0x3c6ef372fe94f82bUL;
  v[11] = 0xa54ff53a5f1d36f1UL;
  v[12] = 0x510e527fade68251UL;
  v[13] = 0x9b05688c2b3e6c1fUL;
  v[14] = 0xe07c265404be4294UL;
  v[15] = 0x5be0cd19137e2179UL;

  ROUND( 0 );
  ROUND( 1 );
  ROUND( 2 );
  ROUND( 3 );
  ROUND( 4 );
  ROUND( 5 );
  ROUND( 6 );
  ROUND( 7 );
  ROUND( 8 );
  ROUND( 9 );
  ROUND( 10 );
  ROUND( 11 );
#undef G
#undef ROUND

  LONG pow    = 0x6a09e667f2bdc928UL ^ v[0] ^ v[8];
  LONG target = g_header[20];

  /**
   * Do a bytewise comparison to see if the
   * pow satisfies the target. We only compare
   * the first 64 bits. This should be fine until
   * asics render this code obsolete.
   */
  if (opencl_memcmp(&pow, &target, 8) <= 0) {
    *g_nonce = nonce;
    *g_match = true;
    return;
  }
}
