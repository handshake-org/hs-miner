#define DO_NOTHING(...) (__VA_ARGS__)
// Cuckoo Cycle, a memory-hard proof-of-work
// Copyright (c) 2013-2016 John Tromp

// The edge-trimming memory optimization is due to Dave Andersen
// http://da-data.blogspot.com/2014/03/a-public-review-of-cuckoo-cycle.html

#include <stdint.h>
#include <string.h>
#include "cuckoo.h"

// d(evice s)ipnode
#if (__CUDA_ARCH__  >= 320) // redefine ROTL to use funnel shifter, 3% speed gain

static __device__ __forceinline__ uint2 operator^ (uint2 a, uint2 b) { return make_uint2(a.x ^ b.x, a.y ^ b.y); }
static __device__ __forceinline__ void operator^= (uint2 &a, uint2 b) { a.x ^= b.x, a.y ^= b.y; }
static __device__ __forceinline__ void operator+= (uint2 &a, uint2 b) {
  asm("{\n\tadd.cc.u32 %0,%2,%4;\n\taddc.u32 %1,%3,%5;\n\t}\n\t"
    : "=r"(a.x), "=r"(a.y) : "r"(a.x), "r"(a.y), "r"(b.x), "r"(b.y));
}
#undef ROTL
__inline__ __device__ uint2 ROTL(const uint2 a, const int offset) {
  uint2 result;
  if (offset >= 32) {
    asm("shf.l.wrap.b32 %0, %1, %2, %3;" : "=r"(result.x) : "r"(a.x), "r"(a.y), "r"(offset));
    asm("shf.l.wrap.b32 %0, %1, %2, %3;" : "=r"(result.y) : "r"(a.y), "r"(a.x), "r"(offset));
  } else {
    asm("shf.l.wrap.b32 %0, %1, %2, %3;" : "=r"(result.x) : "r"(a.y), "r"(a.x), "r"(offset));
    asm("shf.l.wrap.b32 %0, %1, %2, %3;" : "=r"(result.y) : "r"(a.x), "r"(a.y), "r"(offset));
  }
  return result;
}
__device__ __forceinline__ uint2 vectorize(const uint64_t x) {
  uint2 result;
  asm("mov.b64 {%0,%1},%2; \n\t" : "=r"(result.x), "=r"(result.y) : "l"(x));
  return result;
}
__device__ __forceinline__ uint64_t devectorize(uint2 x) {
  uint64_t result;
  asm("mov.b64 %0,{%1,%2}; \n\t" : "=l"(result) : "r"(x.x), "r"(x.y));
  return result;
}
static __device__ node_t dipnode(siphash_keys &keys, edge_t nce, u32 uorv) {
  uint2 nonce = vectorize(2*nce + uorv);
  uint2 v0 = vectorize(keys.k0), v1 = vectorize(keys.k1), v2 = vectorize(keys.k2), v3 = vectorize(keys.k3) ^ nonce;
  SIPROUND; SIPROUND;
  v0 ^= nonce;
  v2 ^= vectorize(0xff);
  SIPROUND; SIPROUND; SIPROUND; SIPROUND;
  return devectorize(v0 ^ v1 ^ v2  ^ v3) & EDGEMASK;
}

#else

static __device__ node_t dipnode(siphash_keys &keys, edge_t nce, u32 uorv) {
  u64 nonce = 2*nce + uorv;
  u64 v0 = keys.k0, v1 = keys.k1, v2 = keys.k2, v3 = keys.k3 ^ nonce;
  SIPROUND; SIPROUND;
  v0 ^= nonce;
  v2 ^= 0xff;
  SIPROUND; SIPROUND; SIPROUND; SIPROUND;
  return (v0 ^ v1 ^ v2  ^ v3) & EDGEMASK;
}

#endif

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <set>

// algorithm parameters
#ifndef PART_BITS
// #bits used to partition edge set processing to save memory
// a value of 0 does no partitioning and is fastest
// a value of 1 partitions in two, making leancu_twice_set the
// same size as leancu_shrinkingset at about 33% slowdown
// higher values are not that interesting
#define PART_BITS 0
#endif

#ifndef IDXSHIFT
// we want sizeof(leancu_cuckoo_hash) == sizeof(leancu_twice_set), so
// CUCKOO_SIZE * sizeof(u64) == TWICE_WORDS * sizeof(u32)
// CUCKOO_SIZE * 2 == TWICE_WORDS
// (NNODES >> IDXSHIFT) * 2 == 2 * ONCE_BITS / 32
// NNODES >> IDXSHIFT == NEDGES >> PART_BITS >> 5
// IDXSHIFT == 1 + PART_BITS + 5
#define IDXSHIFT (PART_BITS + 6)
#endif

#define NODEBITS (EDGEBITS + 1)
#define NNODES (2 * NEDGES)
#define NODEMASK (NNODES-1)

// grow with cube root of size, hardly affected by trimming
#define MAXPATHLEN (8 << (NODEBITS/3))

#define freeCudaAllocs() \
  do { \
    if (ctx.alive.bits) cudaFree(ctx.alive.bits); \
    if (ctx.nonleaf.bits) cudaFree(ctx.nonleaf.bits); \
    if (device_ctx) cudaFree(device_ctx);\
  } while (0)

#define checkCudaErrors(action) \
  do { \
    cudaError_t c = (action); \
    if (c != cudaSuccess) { \
      int32_t code = (int32_t)c; \
      if (code == 0) code = 1; \
      if (code < 0) code = -code; \
      freeCudaAllocs(); \
      return -code; \
    } \
  } while (0)
 
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
  if (code != cudaSuccess) {
    0;
    if (abort) exit(code);
  }
}

// set that starts out full and gets reset by threads on disjoint words
class leancu_shrinkingset {
public:
  u32 *bits;
  __device__ void reset(edge_t n) {
    bits[n/32] |= 1 << (n%32);
  }
  __device__ bool test(node_t n) const {
    return !((bits[n/32] >> (n%32)) & 1);
  }
  __device__ u32 block(node_t n) const {
    return ~bits[n/32];
  }
};

#define PART_MASK ((1 << PART_BITS) - 1)
#define ONCE_BITS (NEDGES >> PART_BITS)
#define TWICE_WORDS ((2 * ONCE_BITS) / 32)

class leancu_twice_set {
public:
  u32 *bits;
  __device__ void reset() {
    memset(bits, 0, TWICE_WORDS * sizeof(u32));
  }
  __device__ void set(node_t u) {
    node_t idx = u/16;
    u32 bit = 1 << (2 * (u%16));
    u32 old = atomicOr(&bits[idx], bit);
    u32 bit2 = bit<<1;
    if ((old & (bit2|bit)) == bit) atomicOr(&bits[idx], bit2);
  }
  __device__ u32 test(node_t u) const {
    return (bits[u/16] >> (2 * (u%16))) & 2;
  }
};

#define CUCKOO_SIZE (NNODES >> IDXSHIFT)
#define CUCKOO_MASK (CUCKOO_SIZE - 1)
// number of (least significant) key bits that survives leftshift by NODEBITS
#define KEYBITS (64-NODEBITS)
#define KEYMASK ((1L << KEYBITS) - 1)
#define MAXDRIFT (1L << (KEYBITS - IDXSHIFT))

class leancu_cuckoo_hash {
public:
  u64 *cuckoo;

  leancu_cuckoo_hash() {
    cuckoo = (u64 *)calloc(CUCKOO_SIZE, sizeof(u64));
    assert(cuckoo != 0);
  }
  ~leancu_cuckoo_hash() {
    free(cuckoo);
  }
  void set(node_t u, node_t v) {
    u64 niew = (u64)u << NODEBITS | v;
    for (node_t ui = u >> IDXSHIFT; ; ui = (ui+1) & CUCKOO_MASK) {
#ifdef ATOMIC
      u64 old = 0;
      if (cuckoo[ui].compare_exchange_strong(old, niew, std::memory_order_relaxed))
        return;
      if ((old >> NODEBITS) == (u & KEYMASK)) {
        cuckoo[ui].store(niew, std::memory_order_relaxed);
#else
      u64 old = cuckoo[ui];
      if (old == 0 || (old >> NODEBITS) == (u & KEYMASK)) {
        cuckoo[ui] = niew;
#endif
        return;
      }
    }
  }
  node_t operator[](node_t u) const {
    for (node_t ui = u >> IDXSHIFT; ; ui = (ui+1) & CUCKOO_MASK) {
#ifdef ATOMIC
      u64 cu = cuckoo[ui].load(std::memory_order_relaxed);
#else
      u64 cu = cuckoo[ui];
#endif
      if (!cu)
        return 0;
      if ((cu >> NODEBITS) == (u & KEYMASK)) {
        assert(((ui - (u >> IDXSHIFT)) & CUCKOO_MASK) < MAXDRIFT);
        return (node_t)(cu & NODEMASK);
      }
    }
  }
};

// arbitrary length of header hashed into siphash key


class leancu_cuckoo_ctx {
public:
  siphash_keys sip_keys;
  leancu_shrinkingset alive;
  leancu_twice_set nonleaf;
  int nthreads;

  leancu_cuckoo_ctx(const u32 n_threads) {
    nthreads = n_threads;
  }
  void setheadernonce(char* headernonce, uint32_t len, const u32 nonce) {
    ((u32 *)headernonce)[len/sizeof(u32)-1] = htole32(nonce); // place nonce at end
    setheader(headernonce, len, &sip_keys);
  }
};

__global__ void count_node_deg(leancu_cuckoo_ctx *ctx, u32 uorv, u32 part) {
  leancu_shrinkingset &alive = ctx->alive;
  leancu_twice_set &nonleaf = ctx->nonleaf;
  siphash_keys sip_keys = ctx->sip_keys; // local copy sip context; 2.5% speed gain
  int id = blockIdx.x * blockDim.x + threadIdx.x;
  for (edge_t block = id*32; block < NEDGES; block += ctx->nthreads*32) {
    u32 alive32 = alive.block(block);
    for (edge_t nonce = block-1; alive32; ) { // -1 compensates for 1-based ffs
      u32 ffs = __ffs(alive32);
      nonce += ffs; alive32 >>= ffs;
      node_t u = dipnode(sip_keys, nonce, uorv);
      if ((u & PART_MASK) == part) {
        nonleaf.set(u >> PART_BITS);
      }
    }
  }
}

__global__ void kill_leaf_edges(leancu_cuckoo_ctx *ctx, u32 uorv, u32 part) {
  leancu_shrinkingset &alive = ctx->alive;
  leancu_twice_set &nonleaf = ctx->nonleaf;
  siphash_keys sip_keys = ctx->sip_keys;
  int id = blockIdx.x * blockDim.x + threadIdx.x;
  for (edge_t block = id*32; block < NEDGES; block += ctx->nthreads*32) {
    u32 alive32 = alive.block(block);
    for (edge_t nonce = block-1; alive32; ) { // -1 compensates for 1-based ffs
      u32 ffs = __ffs(alive32);
      nonce += ffs; alive32 >>= ffs;
      node_t u = dipnode(sip_keys, nonce, uorv);
      if ((u & PART_MASK) == part) {
        if (!nonleaf.test(u >> PART_BITS)) {
          alive.reset(nonce);
        }
      }
    }
  }
}

static u32 path(leancu_cuckoo_hash &cuckoo, node_t u, node_t *us) {
  u32 nu;
  for (nu = 0; u; u = cuckoo[u]) {
    if (nu >= MAXPATHLEN) {
      while (nu-- && us[nu] != u) ;
      if (nu == ~0)
        0;
      else DO_NOTHING("illegal % 4d-cycle\n", MAXPATHLEN-nu);
      return (u32)-1;
    }
    us[nu++] = u;
  }
  return nu-1;
}

typedef std::pair<node_t,node_t> edge;

#include <unistd.h>
#include <stdbool.h>
#include "../common.h"

static int32_t lean_run(
  bool *running,
  uint32_t nthreads,
  uint32_t trims,
  uint32_t tpb,
  uint32_t nonce,
  uint32_t range,
  uint8_t *hdr,
  size_t hdrlen,
  uint8_t *target,
  uint8_t *solution,
  uint32_t *result,
  bool *match
) {
  int argc = 0;
  char *argv[1] = { NULL };
  uint8_t hash[32];
  uint8_t chash[32];
  uint32_t sol[PROOFSIZE];
  bool has_sol = false;
  uint32_t ononce = nonce;
  memset(hash, 0xff, 32);





  const char *header = "";
  int c;
  while ((c = getopt (argc, argv, "h:n:m:r:t:p:")) != -1) {
    switch (c) {
      case 'h':
        header = optarg;
        break;
      case 'n':
        nonce = atoi(optarg);
        break;
      case 'm':
        trims = atoi(optarg);
        break;
      case 't':
        nthreads = atoi(optarg);
        break;
      case 'p':
        tpb = atoi(optarg);
        break;
      case 'r':
        range = atoi(optarg);
        break;
    }
  }
  if (!tpb) // if not set, then default threads per block to roughly square root of threads
    for (tpb = 1; tpb*tpb < nthreads; tpb *= 2) ;

  0;
  if (range > 1)
    0;
  0;

  leancu_cuckoo_ctx ctx(nthreads);
  ctx.alive.bits = NULL;
  ctx.nonleaf.bits = NULL;
  ctx.nonleaf.bits = NULL;

  leancu_cuckoo_ctx *device_ctx = NULL;






  u64 edgeBytes = NEDGES/8, nodeBytes = TWICE_WORDS*sizeof(u32);
  checkCudaErrors(cudaMalloc((void**)&ctx.alive.bits, edgeBytes));
  checkCudaErrors(cudaMalloc((void**)&ctx.nonleaf.bits, nodeBytes));

  int edgeUnit=0, nodeUnit=0;
  u64 eb = edgeBytes, nb = nodeBytes;
  for (; eb >= 1024; eb>>=10) edgeUnit++;
  for (; nb >= 1024; nb>>=10) nodeUnit++;
  DO_NOTHING("Using %d%cB edge and %d%cB node memory.\n",
     (int)eb, " KMGT"[edgeUnit], (int)nb, " KMGT"[nodeUnit]);


  checkCudaErrors(cudaMalloc((void**)&device_ctx, sizeof(leancu_cuckoo_ctx)));

  cudaEvent_t start, stop;
  checkCudaErrors(cudaEventCreate(&start));
  checkCudaErrors(cudaEventCreate(&stop));

  for (uint32_t r = 0; r < range; r++) {
    if (!*running)
      break;
 
    cudaEventRecord(start, NULL);
    checkCudaErrors(cudaMemset(ctx.alive.bits, 0, edgeBytes));
    ctx.setheadernonce((char *)hdr, hdrlen, nonce + r);
    cudaMemcpy(device_ctx, &ctx, sizeof(leancu_cuckoo_ctx), cudaMemcpyHostToDevice);
    for (u32 round=0; round < trims; round++) {
      for (u32 uorv = 0; uorv < 2; uorv++) {
        for (u32 part = 0; part <= PART_MASK; part++) {
          checkCudaErrors(cudaMemset(ctx.nonleaf.bits, 0, nodeBytes));
          count_node_deg<<<nthreads/tpb,tpb >>>(device_ctx, uorv, part);
          kill_leaf_edges<<<nthreads/tpb,tpb >>>(device_ctx, uorv, part);
        }
      }
    }
  
    u64 *bits;
    bits = (u64 *)calloc(NEDGES/64, sizeof(u64));

    if (!bits) {
      freeCudaAllocs();
      return HS_ENOMEM;
    }

    if (!*running) {
      free(bits);
      freeCudaAllocs();
      return has_sol ? HS_SUCCESS : HS_ENOSOLUTION;
    }
 
    cudaMemcpy(bits, ctx.alive.bits, (NEDGES/64) * sizeof(u64), cudaMemcpyDeviceToHost);

    cudaEventRecord(stop, NULL);
    cudaEventSynchronize(stop);
    float duration;
    cudaEventElapsedTime(&duration, start, stop);
    u32 cnt = 0;
    for (int i = 0; i < NEDGES/64; i++)
      cnt += __builtin_popcountll(~bits[i]);
    u32 load = (u32)(100L * cnt / CUCKOO_SIZE);
    DO_NOTHING("nonce %d: %d trims completed in %.3f seconds final load %d%%\n",
            nonce+r, trims, duration / 1000.0f, load);
  
    if (load >= 90) {
      0;
      free(bits);
      freeCudaAllocs();
      return HS_EMAXLOAD;
    }
  
    leancu_cuckoo_hash &cuckoo = *(new leancu_cuckoo_hash());
    node_t us[MAXPATHLEN], vs[MAXPATHLEN];
    for (edge_t block = 0; block < NEDGES; block += 64) {
      u64 alive64 = ~bits[block/64];
      for (edge_t nonce = block-1; alive64; ) { // -1 compensates for 1-based ffs
        u32 ffs = __builtin_ffsll(alive64);
        nonce += ffs; alive64 >>= ffs;
        node_t u0=sipnode(&ctx.sip_keys, nonce, 0), v0=sipnode(&ctx.sip_keys, nonce, 1);
        if (u0) {
          u32 nu = path(cuckoo, u0, us), nv = path(cuckoo, v0, vs);

          if ((int32_t)nu == -1 || (int32_t)nv == -1) {
            delete &cuckoo;
            free(bits);
            freeCudaAllocs();
            return HS_EBADPATH;
          }
 
          if (us[nu] == vs[nv]) {
            u32 min = nu < nv ? nu : nv;
            for (nu -= min, nv -= min; us[nu] != vs[nv]; nu++, nv++) ;
            u32 len = nu + nv + 1;
            0;
            if (len == PROOFSIZE) {
              0;
              std::set<edge> cycle;
              u32 n = 0;
              cycle.insert(edge(*us, *vs));
              while (nu--)
                cycle.insert(edge(us[(nu+1)&~1], us[nu|1])); // u's in even position; v's in odd
              while (nv--)
                cycle.insert(edge(vs[nv|1], vs[(nv+1)&~1])); // u's in odd position; v's in even
              for (edge_t blk = 0; blk < NEDGES; blk += 64) {
                u64 alv64 = ~bits[blk/64];
                for (edge_t nce = blk-1; alv64; ) { // -1 compensates for 1-based ffs
                  u32 ffs = __builtin_ffsll(alv64);
                  nce += ffs; alv64 >>= ffs;
                  edge e(sipnode(&ctx.sip_keys, nce, 0), sipnode(&ctx.sip_keys, nce, 1));
                  if (cycle.find(e) != cycle.end()) {
                    sol[n] = nce;
                    if (PROOFSIZE > 2)
                      cycle.erase(e);
                    n++;
                  }
                  if (ffs & 64) break; // can't shift by 64
                }
              }
              assert(n==PROOFSIZE);


              hs_hash_solution(sol, chash);

              if (memcmp(chash, hash, 32) <= 0) {
                *result = ononce + r;
                for (int32_t i = 0; i < PROOFSIZE; i++)
                  hs_write_u32(&solution[i * 4], sol[i]);
                memcpy(hash, chash, 32);
                has_sol = true;
              }

              if (memcmp(chash, target, 32) <= 0) {
                *match = true;
                delete &cuckoo;
                free(bits);
                freeCudaAllocs();
                return HS_SUCCESS;
              }

out:
              if (!*running) {
                delete &cuckoo;
                free(bits);
                freeCudaAllocs();
                return has_sol ? HS_SUCCESS : HS_ENOSOLUTION;
              }
 
              0;
            }
          } else if (nu < nv) {
            while (nu--)
              cuckoo.set(us[nu+1], us[nu]);
            cuckoo.set(u0, v0);
          } else {
            while (nv--)
              cuckoo.set(vs[nv+1], vs[nv]);
            cuckoo.set(v0, u0);
          }
        }
        if (ffs & 64) break; // can't shift by 64
      }
    }

    delete &cuckoo;
    free(bits);
  }

  freeCudaAllocs();

  return has_sol ? HS_SUCCESS : HS_ENOSOLUTION;
}
