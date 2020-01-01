#include <stdio.h>
#include "common.h"
#include "blake2.h"
#include "sha3.h"
#include "header.h"
#include "error.h"

typedef unsigned char BYTE;
typedef unsigned int  WORD;
typedef unsigned long long LONG;

#define BLAKE2B_ROUNDS 12
#define BLAKE2B_BLOCK_LENGTH 128
#define BLAKE2B_CHAIN_SIZE 8
#define BLAKE2B_CHAIN_LENGTH (BLAKE2B_CHAIN_SIZE * sizeof(int64_t))
#define BLAKE2B_STATE_SIZE 16
#define BLAKE2B_STATE_LENGTH (BLAKE2B_STATE_SIZE * sizeof(int64_t))
typedef struct {

    WORD digestlen;
    BYTE key[64];
    WORD keylen;

    BYTE buff[BLAKE2B_BLOCK_LENGTH];
    int64_t chain[BLAKE2B_CHAIN_SIZE];
    int64_t state[BLAKE2B_STATE_SIZE];

    WORD pos;
    LONG t0;
    LONG t1;
    LONG f0;

} cuda_blake2b_ctx_t;
typedef cuda_blake2b_ctx_t CUDA_BLAKE2B_CTX;

__constant__ CUDA_BLAKE2B_CTX c_CTX;

__constant__ LONG BLAKE2B_IVS[8] =
{
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b,
        0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f,
        0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
};

const LONG CPU_BLAKE2B_IVS[8] =
{
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b,
        0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f,
        0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
};

void cpu_blake2b_init(cuda_blake2b_ctx_t *ctx, BYTE* key, WORD keylen, WORD digestbitlen)
{
    memset(ctx, 0, sizeof(cuda_blake2b_ctx_t));
    memcpy(ctx->buff, key, keylen);
    memcpy(ctx->key, key, keylen);
    ctx->keylen = keylen;

    ctx->digestlen = digestbitlen >> 3;
    ctx->pos = 0;
    ctx->t0 = 0;
    ctx->t1 = 0;
    ctx->f0 = 0;
    ctx->chain[0] = CPU_BLAKE2B_IVS[0] ^ (ctx->digestlen | (ctx->keylen << 8) | 0x1010000);
    ctx->chain[1] = CPU_BLAKE2B_IVS[1];
    ctx->chain[2] = CPU_BLAKE2B_IVS[2];
    ctx->chain[3] = CPU_BLAKE2B_IVS[3];
    ctx->chain[4] = CPU_BLAKE2B_IVS[4];
    ctx->chain[5] = CPU_BLAKE2B_IVS[5];
    ctx->chain[6] = CPU_BLAKE2B_IVS[6];
    ctx->chain[7] = CPU_BLAKE2B_IVS[7];


    if (keylen > 0)
        ctx->pos = BLAKE2B_BLOCK_LENGTH;
}



__constant__ unsigned char BLAKE2B_SIGMAS[12][16] =
{
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

__device__ LONG cuda_blake2b_leuint64(BYTE *in)
{
    LONG a;
    memcpy(&a, in, 8);
    return a;

/* If memory is not little endian
BYTE *a = (BYTE *)in;
return ((LONG)(a[0]) << 0) | ((LONG)(a[1]) << 8) | ((LONG)(a[2]) << 16) | ((LONG)(a[3]) << 24) |((LONG)(a[4]) << 32)
    | ((LONG)(a[5]) << 40) | ((LONG)(a[6]) << 48) | 	((LONG)(a[7]) << 56);
 */
}

__device__ LONG cuda_blake2b_ROTR64(LONG a, BYTE b)
{
    return (a >> b) | (a << (64 - b));
}

__device__ void cuda_blake2b_G(cuda_blake2b_ctx_t *ctx, int64_t m1, int64_t m2, int32_t a, int32_t b, int32_t c, int32_t d)
{
    ctx->state[a] = ctx->state[a] + ctx->state[b] + m1;
    ctx->state[d] = cuda_blake2b_ROTR64(ctx->state[d] ^ ctx->state[a], 32);
    ctx->state[c] = ctx->state[c] + ctx->state[d];
    ctx->state[b] = cuda_blake2b_ROTR64(ctx->state[b] ^ ctx->state[c], 24);
    ctx->state[a] = ctx->state[a] + ctx->state[b] + m2;
    ctx->state[d] = cuda_blake2b_ROTR64(ctx->state[d] ^ ctx->state[a], 16);
    ctx->state[c] = ctx->state[c] + ctx->state[d];
    ctx->state[b] = cuda_blake2b_ROTR64(ctx->state[b] ^ ctx->state[c], 63);
}

__device__ __forceinline__ void cuda_blake2b_init_state(cuda_blake2b_ctx_t *ctx)
{
    memcpy(ctx->state, ctx->chain, BLAKE2B_CHAIN_LENGTH);
    for (int i = 0; i < 4; i++)
        ctx->state[BLAKE2B_CHAIN_SIZE + i] = BLAKE2B_IVS[i];

    ctx->state[12] = ctx->t0 ^ BLAKE2B_IVS[4];
    ctx->state[13] = ctx->t1 ^ BLAKE2B_IVS[5];
    ctx->state[14] = ctx->f0 ^ BLAKE2B_IVS[6];
    ctx->state[15] = BLAKE2B_IVS[7];
}

__device__ __forceinline__ void cuda_blake2b_compress(cuda_blake2b_ctx_t *ctx, BYTE* in, WORD inoffset)
{
    cuda_blake2b_init_state(ctx);

    LONG  m[16] = {0};
    for (int j = 0; j < 16; j++)
        m[j] = cuda_blake2b_leuint64(in + inoffset + (j << 3));

    for (int round = 0; round < BLAKE2B_ROUNDS; round++)
    {
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][0]], m[BLAKE2B_SIGMAS[round][1]], 0, 4, 8, 12);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][2]], m[BLAKE2B_SIGMAS[round][3]], 1, 5, 9, 13);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][4]], m[BLAKE2B_SIGMAS[round][5]], 2, 6, 10, 14);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][6]], m[BLAKE2B_SIGMAS[round][7]], 3, 7, 11, 15);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][8]], m[BLAKE2B_SIGMAS[round][9]], 0, 5, 10, 15);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][10]], m[BLAKE2B_SIGMAS[round][11]], 1, 6, 11, 12);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][12]], m[BLAKE2B_SIGMAS[round][13]], 2, 7, 8, 13);
        cuda_blake2b_G(ctx, m[BLAKE2B_SIGMAS[round][14]], m[BLAKE2B_SIGMAS[round][15]], 3, 4, 9, 14);
    }

    for (int offset = 0; offset < BLAKE2B_CHAIN_SIZE; offset++)
        ctx->chain[offset] = ctx->chain[offset] ^ ctx->state[offset] ^ ctx->state[offset + 8];
}

__device__ void cuda_blake2b_init(cuda_blake2b_ctx_t *ctx, BYTE* key, WORD keylen, WORD digestbitlen)
{
    memset(ctx, 0, sizeof(cuda_blake2b_ctx_t));

    ctx->keylen = keylen;
    ctx->digestlen = digestbitlen >> 3;
    ctx->pos = 0;
    ctx->t0 = 0;
    ctx->t1 = 0;
    ctx->f0 = 0;
    ctx->chain[0] = BLAKE2B_IVS[0] ^ (ctx->digestlen | (ctx->keylen << 8) | 0x1010000);
    ctx->chain[1] = BLAKE2B_IVS[1];
    ctx->chain[2] = BLAKE2B_IVS[2];
    ctx->chain[3] = BLAKE2B_IVS[3];
    ctx->chain[4] = BLAKE2B_IVS[4];
    ctx->chain[5] = BLAKE2B_IVS[5];
    ctx->chain[6] = BLAKE2B_IVS[6];
    ctx->chain[7] = BLAKE2B_IVS[7];

    memcpy(ctx->buff, key, keylen);
    memcpy(ctx->key, key, keylen);

    if (keylen > 0)
        ctx->pos = BLAKE2B_BLOCK_LENGTH;
}

__device__ void cuda_blake2b_update(cuda_blake2b_ctx_t *ctx, BYTE* in, LONG inlen)
{
    if (inlen == 0)
        return;

    WORD start = 0;
    int64_t in_index = 0, block_index = 0;

    if (ctx->pos)
    {
        start = BLAKE2B_BLOCK_LENGTH - ctx->pos;
        if (start < inlen){
            memcpy(ctx->buff + ctx->pos, in, start);
            ctx->t0 += BLAKE2B_BLOCK_LENGTH;

            if (ctx->t0 == 0) ctx->t1++;

            cuda_blake2b_compress(ctx, ctx->buff, 0);
            ctx->pos = 0;
            memset(ctx->buff, 0, BLAKE2B_BLOCK_LENGTH);
        } else {
            memcpy(ctx->buff + ctx->pos, in, inlen);//read the whole *in
            ctx->pos += inlen;
            return;
        }
    }

    block_index =  inlen - BLAKE2B_BLOCK_LENGTH;
    for (in_index = start; in_index < block_index; in_index += BLAKE2B_BLOCK_LENGTH)
    {
        ctx->t0 += BLAKE2B_BLOCK_LENGTH;
        if (ctx->t0 == 0)
            ctx->t1++;

        cuda_blake2b_compress(ctx, in, in_index);
    }

    memcpy(ctx->buff, in + in_index, inlen - in_index);
    ctx->pos += inlen - in_index;
}

__device__ void cuda_blake2b_final(cuda_blake2b_ctx_t *ctx, BYTE* out)
{
    ctx->f0 = 0xFFFFFFFFFFFFFFFFL;
    ctx->t0 += ctx->pos;
    if (ctx->pos > 0 && ctx->t0 == 0)
        ctx->t1++;

    cuda_blake2b_compress(ctx, ctx->buff, 0);
    memset(ctx->buff, 0, BLAKE2B_BLOCK_LENGTH);
    memset(ctx->state, 0, BLAKE2B_STATE_LENGTH);

    int i8 = 0;
    for (int i = 0; i < BLAKE2B_CHAIN_SIZE && ((i8 = i * 8) < ctx->digestlen); i++)
    {
        BYTE * BYTEs = (BYTE*)(&ctx->chain[i]);
        if (i8 < ctx->digestlen - 8)
            memcpy(out + i8, BYTEs, 8);
        else
            memcpy(out + i8, BYTEs, ctx->digestlen - i8);
    }
}

__global__ void kernel_blake2b_hash(BYTE* indata, WORD inlen, BYTE* outdata, WORD n_batch, WORD BLAKE2B_BLOCK_SIZE)
{
    WORD thread = blockIdx.x * blockDim.x + threadIdx.x;
    if (thread >= n_batch)
    {
        return;
    }
    BYTE* in = indata  + thread * inlen;
    BYTE* out = outdata  + thread * BLAKE2B_BLOCK_SIZE;
    CUDA_BLAKE2B_CTX ctx = c_CTX;
    //if not precomputed CTX, call cuda_blake2b_init() with key
    cuda_blake2b_update(&ctx, in, inlen);
    cuda_blake2b_final(&ctx, out);
}

#define KECCAK_ROUND 24
#define KECCAK_STATE_SIZE 25
#define KECCAK_Q_SIZE 192

__constant__ LONG CUDA_KECCAK_CONSTS[24] = { 0x0000000000000001, 0x0000000000008082,
                                          0x800000000000808a, 0x8000000080008000, 0x000000000000808b, 0x0000000080000001, 0x8000000080008081,
                                          0x8000000000008009, 0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
                                          0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003, 0x8000000000008002,
                                          0x8000000000000080, 0x000000000000800a, 0x800000008000000a, 0x8000000080008081, 0x8000000000008080,
                                          0x0000000080000001, 0x8000000080008008 };

typedef struct {

    BYTE sha3_flag;
    WORD digestbitlen;
    LONG rate_bits;
    LONG rate_BYTEs;
    LONG absorb_round;

    int64_t state[KECCAK_STATE_SIZE];
    BYTE q[KECCAK_Q_SIZE];

    LONG bits_in_queue;

} cuda_keccak_ctx_t;
typedef cuda_keccak_ctx_t CUDA_KECCAK_CTX;

__device__ LONG cuda_keccak_leuint64(void *in)
{
    LONG a;
    memcpy(&a, in, 8);
    return a;
}

__device__ int64_t cuda_keccak_MIN(int64_t a, int64_t b)
{
    if (a > b) return b;
    return a;
}

__device__ LONG cuda_keccak_UMIN(LONG a, LONG b)
{
    if (a > b) return b;
    return a;
}

__device__ void cuda_keccak_extract(cuda_keccak_ctx_t *ctx)
{
    LONG len = ctx->rate_bits >> 6;
    int64_t a;
    int s = sizeof(LONG);

    for (int i = 0;i < len;i++) {
        a = cuda_keccak_leuint64((int64_t*)&ctx->state[i]);
        memcpy(ctx->q + (i * s), &a, s);
    }
}

__device__ __forceinline__ LONG cuda_keccak_ROTL64(LONG a, LONG  b)
{
    return (a << b) | (a >> (64 - b));
}

__device__ void cuda_keccak_permutations(cuda_keccak_ctx_t * ctx)
{

    int64_t* A = ctx->state;;

    int64_t *a00 = A, *a01 = A + 1, *a02 = A + 2, *a03 = A + 3, *a04 = A + 4;
    int64_t *a05 = A + 5, *a06 = A + 6, *a07 = A + 7, *a08 = A + 8, *a09 = A + 9;
    int64_t *a10 = A + 10, *a11 = A + 11, *a12 = A + 12, *a13 = A + 13, *a14 = A + 14;
    int64_t *a15 = A + 15, *a16 = A + 16, *a17 = A + 17, *a18 = A + 18, *a19 = A + 19;
    int64_t *a20 = A + 20, *a21 = A + 21, *a22 = A + 22, *a23 = A + 23, *a24 = A + 24;

    for (int i = 0; i < KECCAK_ROUND; i++) {

        /* Theta */
        int64_t c0 = *a00 ^ *a05 ^ *a10 ^ *a15 ^ *a20;
        int64_t c1 = *a01 ^ *a06 ^ *a11 ^ *a16 ^ *a21;
        int64_t c2 = *a02 ^ *a07 ^ *a12 ^ *a17 ^ *a22;
        int64_t c3 = *a03 ^ *a08 ^ *a13 ^ *a18 ^ *a23;
        int64_t c4 = *a04 ^ *a09 ^ *a14 ^ *a19 ^ *a24;

        int64_t d1 = cuda_keccak_ROTL64(c1, 1) ^ c4;
        int64_t d2 = cuda_keccak_ROTL64(c2, 1) ^ c0;
        int64_t d3 = cuda_keccak_ROTL64(c3, 1) ^ c1;
        int64_t d4 = cuda_keccak_ROTL64(c4, 1) ^ c2;
        int64_t d0 = cuda_keccak_ROTL64(c0, 1) ^ c3;

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
        c1 = cuda_keccak_ROTL64(*a01, 1);
        *a01 = cuda_keccak_ROTL64(*a06, 44);
        *a06 = cuda_keccak_ROTL64(*a09, 20);
        *a09 = cuda_keccak_ROTL64(*a22, 61);
        *a22 = cuda_keccak_ROTL64(*a14, 39);
        *a14 = cuda_keccak_ROTL64(*a20, 18);
        *a20 = cuda_keccak_ROTL64(*a02, 62);
        *a02 = cuda_keccak_ROTL64(*a12, 43);
        *a12 = cuda_keccak_ROTL64(*a13, 25);
        *a13 = cuda_keccak_ROTL64(*a19, 8);
        *a19 = cuda_keccak_ROTL64(*a23, 56);
        *a23 = cuda_keccak_ROTL64(*a15, 41);
        *a15 = cuda_keccak_ROTL64(*a04, 27);
        *a04 = cuda_keccak_ROTL64(*a24, 14);
        *a24 = cuda_keccak_ROTL64(*a21, 2);
        *a21 = cuda_keccak_ROTL64(*a08, 55);
        *a08 = cuda_keccak_ROTL64(*a16, 45);
        *a16 = cuda_keccak_ROTL64(*a05, 36);
        *a05 = cuda_keccak_ROTL64(*a03, 28);
        *a03 = cuda_keccak_ROTL64(*a18, 21);
        *a18 = cuda_keccak_ROTL64(*a17, 15);
        *a17 = cuda_keccak_ROTL64(*a11, 10);
        *a11 = cuda_keccak_ROTL64(*a07, 6);
        *a07 = cuda_keccak_ROTL64(*a10, 3);
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


__device__ void cuda_keccak_absorb(cuda_keccak_ctx_t *ctx, BYTE* in)
{

    LONG offset = 0;
    for (LONG i = 0; i < ctx->absorb_round; ++i) {
        ctx->state[i] ^= cuda_keccak_leuint64(in + offset);
        offset += 8;
    }

    cuda_keccak_permutations(ctx);
}

__device__ void cuda_keccak_pad(cuda_keccak_ctx_t *ctx)
{
    ctx->q[ctx->bits_in_queue >> 3] |= (1L << (ctx->bits_in_queue & 7));

    if (++(ctx->bits_in_queue) == ctx->rate_bits) {
        cuda_keccak_absorb(ctx, ctx->q);
        ctx->bits_in_queue = 0;
    }

    LONG full = ctx->bits_in_queue >> 6;
    LONG partial = ctx->bits_in_queue & 63;

    LONG offset = 0;
    for (int i = 0; i < full; ++i) {
        ctx->state[i] ^= cuda_keccak_leuint64(ctx->q + offset);
        offset += 8;
    }

    if (partial > 0) {
        LONG mask = (1L << partial) - 1;
        ctx->state[full] ^= cuda_keccak_leuint64(ctx->q + offset) & mask;
    }

    ctx->state[(ctx->rate_bits - 1) >> 6] ^= 9223372036854775808ULL;/* 1 << 63 */

    cuda_keccak_permutations(ctx);
    cuda_keccak_extract(ctx);

    ctx->bits_in_queue = ctx->rate_bits;
}

/*
 * Digestbitlen must be 128 224 256 288 384 512
 */
__device__ void cuda_keccak_init(cuda_keccak_ctx_t *ctx, WORD digestbitlen)
{
    memset(ctx, 0, sizeof(cuda_keccak_ctx_t));
    ctx->sha3_flag = 1;
    ctx->digestbitlen = digestbitlen;
    ctx->rate_bits = 1600 - ((ctx->digestbitlen) << 1);
    ctx->rate_BYTEs = ctx->rate_bits >> 3;
    ctx->absorb_round = ctx->rate_bits >> 6;
    ctx->bits_in_queue = 0;
}

/*
 * Digestbitlen must be 224 256 384 512
 */
__device__ void cuda_keccak_sha3_init(cuda_keccak_ctx_t *ctx, WORD digestbitlen)
{
    cuda_keccak_init(ctx, digestbitlen);
    ctx->sha3_flag = 1;
}

__device__ void cuda_keccak_update(cuda_keccak_ctx_t *ctx, BYTE *in, LONG inlen)
{
    int64_t BYTEs = ctx->bits_in_queue >> 3;
    int64_t count = 0;
    while (count < inlen) {
        if (BYTEs == 0 && count <= ((int64_t)(inlen - ctx->rate_BYTEs))) {
            do {
                cuda_keccak_absorb(ctx, in + count);
                count += ctx->rate_BYTEs;
            } while (count <= ((int64_t)(inlen - ctx->rate_BYTEs)));
        } else {
            int64_t partial = cuda_keccak_MIN(ctx->rate_BYTEs - BYTEs, inlen - count);
            memcpy(ctx->q + BYTEs, in + count, partial);

            BYTEs += partial;
            count += partial;

            if (BYTEs == ctx->rate_BYTEs) {
                cuda_keccak_absorb(ctx, ctx->q);
                BYTEs = 0;
            }
        }
    }
    ctx->bits_in_queue = BYTEs << 3;
}

__device__ void cuda_keccak_final(cuda_keccak_ctx_t *ctx, BYTE *out)
{
    if (ctx->sha3_flag) {
        int mask = (1 << 2) - 1;
        ctx->q[ctx->bits_in_queue >> 3] = (BYTE)(0x02 & mask);
        ctx->bits_in_queue += 2;
    }

    cuda_keccak_pad(ctx);
    LONG i = 0;

    while (i < ctx->digestbitlen) {
        if (ctx->bits_in_queue == 0) {
            cuda_keccak_permutations(ctx);
            cuda_keccak_extract(ctx);
            ctx->bits_in_queue = ctx->rate_bits;
        }

        LONG partial_block = cuda_keccak_UMIN(ctx->bits_in_queue, ctx->digestbitlen - i);
        memcpy(out + (i >> 3), ctx->q + (ctx->rate_BYTEs - (ctx->bits_in_queue >> 3)), partial_block >> 3);
        ctx->bits_in_queue -= partial_block;
        i += partial_block;
    }
}

__global__ void kernel_keccak_hash(BYTE* indata, WORD inlen, BYTE* outdata, WORD n_batch, WORD KECCAK_BLOCK_SIZE)
{
    WORD thread = blockIdx.x * blockDim.x + threadIdx.x;
    if (thread >= n_batch)
    {
        return;
    }
    BYTE* in = indata  + thread * inlen;
    BYTE* out = outdata  + thread * KECCAK_BLOCK_SIZE;
    CUDA_KECCAK_CTX ctx;
    cuda_keccak_init(&ctx, KECCAK_BLOCK_SIZE << 3);
    cuda_keccak_update(&ctx, in, inlen);
    cuda_keccak_final(&ctx, out);
}


/*
 *  nonce - 4
 *  time - 8
 *  padding - 20
 *  prev_block - 32
 *  tree_root - 32
 *  mask - 32
 *  extra_nonce - 24
 *  reserved_root - 32
 *  witness_root - 32
 *  merkle_root - 32
 *  version - 4
 *  bits - 4
 *
 */
__constant__ uint8_t header[256];

__global__ void kernel_hs_hash(uint8_t *out, unsigned int threads)
{
    WORD thread = blockIdx.x * blockDim.x + threadIdx.x;
    if (thread >= threads)
    {
        return;
    }

    CUDA_BLAKE2B_CTX b_ctx;
    CUDA_KECCAK_CTX s_ctx;

    uint8_t *hash = out + thread * 32;

    uint32_t nonce;
    memcpy(&nonce, header, 4);

    uint64_t time;
    memcpy(&time, header + 4, 8);

    uint8_t padding[20];
    memcpy(padding, header + 12, 20);

    uint8_t prev_block[32];
    memcpy(prev_block, header + 32, 32);

    uint8_t tree_root[32];
    memcpy(tree_root, header + 64, 32);

    uint8_t mask_hash[32];
    memcpy(mask_hash, header + 96, 32);

    uint8_t extra_nonce[24];
    memcpy(extra_nonce, header + 128, 24);

    uint8_t reserved_root[32];
    memcpy(reserved_root, header + 152, 32);

    uint8_t witness_root[32];
    memcpy(witness_root, header + 184, 32);

    uint8_t merkle_root[32];
    memcpy(merkle_root, header + 216, 32);

    uint32_t version;
    memcpy(&version, header + 248, 4);

    uint32_t bits;
    memcpy(&bits, header + 252, 4);

    uint8_t pad[20];
    uint8_t pad8[8];
    uint8_t pad32[32];

    size_t i;

    assert(header && pad);
    assert(header && pad8);
    assert(header && pad32);

    for (i = 0; i < 8; i++)
      pad8[i] = prev_block[i % 32] ^ tree_root[i % 32];

    for (i = 0; i < 20; i++)
      pad[i] = prev_block[i % 32] ^ tree_root[i % 32];


    for (i = 0; i < 32; i++)
      pad32[i] = prev_block[i % 32] ^ tree_root[i % 32];

    nonce += thread;

    uint8_t pre[128];
    uint8_t sub[128];
    uint8_t left[64];
    uint8_t right[32];
    uint8_t sub_hash[32];
    uint8_t commit_hash[32];

    // subheader
    memcpy(sub, extra_nonce, 24);
    memcpy(sub + 24, reserved_root, 32);
    memcpy(sub + 56, witness_root, 32);
    memcpy(sub + 88, merkle_root, 32);
    memcpy(sub + 120, &version, 4);
    memcpy(sub + 124, &bits, 4);

    // sub hash
    cuda_blake2b_init(&b_ctx, NULL, 0, 256);
    cuda_blake2b_update(&b_ctx, sub, 128);
    cuda_blake2b_final(&b_ctx, sub_hash);

    // commit hash
    cuda_blake2b_init(&b_ctx, NULL, 0, 256);
    cuda_blake2b_update(&b_ctx, sub_hash, 32);
    cuda_blake2b_update(&b_ctx, mask_hash, 32);
    cuda_blake2b_final(&b_ctx, commit_hash);

    // preheader
    memcpy(pre, &nonce, 4);
    memcpy(pre + 4, &time, 8);
    memcpy(pre + 12, pad, 20);
    memcpy(pre + 32, prev_block, 32);
    memcpy(pre + 64, tree_root, 32);
    memcpy(pre + 96, commit_hash, 32);

    // Generate left.
    cuda_blake2b_init(&b_ctx, NULL, 0, 512);
    cuda_blake2b_update(&b_ctx, pre, 128);
    cuda_blake2b_final(&b_ctx, left);

    // Generate right.
    cuda_keccak_init(&s_ctx, 256);
    cuda_keccak_update(&s_ctx, pre, 128);
    cuda_keccak_update(&s_ctx, pad8, 8);
    cuda_keccak_final(&s_ctx, right);

    // Generate hash.
    cuda_blake2b_init(&b_ctx, NULL, 0, 256);
    cuda_blake2b_update(&b_ctx, left, 64);
    cuda_blake2b_update(&b_ctx, pad32, 32);
    cuda_blake2b_update(&b_ctx, right, 32);
    cuda_blake2b_final(&b_ctx, hash);
}

int32_t hs_cuda_run(hs_options_t *options, uint32_t *result, bool *match)
{
    uint8_t *out;
    uint8_t *cuda_outdata;
    uint8_t *hash;

    out = (uint8_t*)malloc(sizeof(uint8_t) * 32 * options->threads);
    hash = (uint8_t*)malloc(sizeof(uint8_t) *  32);
    cudaMalloc(&cuda_outdata, sizeof(uint8_t) * 32 * options->threads);
    cudaMemcpyToSymbol(header, options->header, 256);

    kernel_hs_hash<<< options->grids, options->blocks >>>(cuda_outdata, options->threads);
    cudaMemcpy(out, cuda_outdata, 32 * options->threads, cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();
    cudaError_t error = cudaGetLastError();
    if (error != cudaSuccess) {
        printf("error hs cuda hash: %s \n", cudaGetErrorString(error));
        // TOOD: cudaFree?
        return HS_ENOSOLUTION;
    }
    cudaFree(cuda_outdata);

    for (int i=0; i < options->threads; i++) {
        memcpy(hash, out + 32 * i, 32);

        if (memcmp(hash, options->target, 32) <= 0) {
            free(out);
            free(hash);

            *result = i;
            *match = true;
            return HS_SUCCESS;
        }
    }

    free(out);
    free(hash);
    return HS_ENOSOLUTION;
}
