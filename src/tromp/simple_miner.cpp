#define DO_NOTHING(...) (__VA_ARGS__)
#include <stdbool.h>
// Cuckoo Cycle, a memory-hard proof-of-work
// Copyright (c) 2013-2016 John Tromp

#include "cuckoo.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <unistd.h>
#include <sys/time.h>
#include <set>
#include "../common.h"

// assume EDGEBITS < 31
#define NNODES (2 * NEDGES)
#define MAXPATHLEN 8192

class simple_cuckoo_ctx {
public:
  siphash_keys sip_keys;
  edge_t easiness;
  node_t *cuckoo;

  simple_cuckoo_ctx(const char* header, const u32 headerlen, const u32 nonce, edge_t easy_ness) {
    easiness = easy_ness;
    cuckoo = (node_t *)calloc(1+NNODES, sizeof(node_t));
    assert(cuckoo != 0);
  }
  u64 bytes() {
    return (u64)(1+NNODES) * sizeof(node_t);
  }
  ~simple_cuckoo_ctx() {
    free(cuckoo);
  }
  void setheadernonce(char* const headernonce, const u32 len, const u32 nonce) {
    ((u32 *)headernonce)[len/sizeof(u32)-1] = htole32(nonce); // place nonce at end
    setheader(headernonce, len, &sip_keys);
    memset(cuckoo, 0, (u64)(1+NNODES) * sizeof(node_t));
  }
  int path(node_t *cuckoo, node_t u, node_t *us) {
    int nu;
    for (nu = 0; u; u = cuckoo[u]) {
      if (++nu >= MAXPATHLEN) {
        while (nu-- && us[nu] != u) ;
        if (nu < 0)
          0;
        else DO_NOTHING("illegal % 4d-cycle\n", MAXPATHLEN-nu);
        exit(0);
      }
      us[nu] = u;
    }
    return nu;
  }
  
  typedef std::pair<node_t,node_t> edge;
  
  void solution(u32 *sol, node_t *us, int nu, node_t *vs, int nv) {
    std::set<edge> cycle;
    unsigned n;
    cycle.insert(edge(*us, *vs));
    while (nu--)
      cycle.insert(edge(us[(nu+1)&~1], us[nu|1])); // u's in even position; v's in odd
    while (nv--)
      cycle.insert(edge(vs[nv|1], vs[(nv+1)&~1])); // u's in odd position; v's in even
    0;
    for (edge_t nonce = n = 0; nonce < easiness; nonce++) {
      edge e(sipnode(&sip_keys, nonce, 0), sipnode(&sip_keys, nonce, 1));
      if (cycle.find(e) != cycle.end()) {
        0;
        if (PROOFSIZE > 2)
          cycle.erase(e);
        sol[n++] = nonce;
      }
    }
    0;
  }
  bool solve(u32 *sol) {
    node_t us[MAXPATHLEN], vs[MAXPATHLEN];
    for (node_t nonce = 0; nonce < easiness; nonce++) {
      node_t u0 = sipnode(&sip_keys, nonce, 0);
      if (u0 == 0) continue; // reserve 0 as nil; v0 guaranteed non-zero
      node_t v0 = sipnode(&sip_keys, nonce, 1);
      node_t u = cuckoo[u0], v = cuckoo[v0];
      us[0] = u0;
      vs[0] = v0;
  #ifdef SHOW
      for (unsigned j=1; j<NNODES; j++)
        if (!cuckoo[j]) DO_NOTHING("%2d:   ",j);
        else           DO_NOTHING("%2d:%02d ",j,cuckoo[j]);
      0;
  #endif
      int nu = path(cuckoo, u, us), nv = path(cuckoo, v, vs);
      if (us[nu] == vs[nv]) {
        int min = nu < nv ? nu : nv;
        for (nu -= min, nv -= min; us[nu] != vs[nv]; nu++, nv++) ;
        int len = nu + nv + 1;
        0;
        if (len == PROOFSIZE) {
          solution(sol, us, nu, vs, nv);
          return true;
        }
        continue;
      }
      if (nu < nv) {
        while (nu--)
          cuckoo[us[nu+1]] = us[nu];
        cuckoo[u0] = v0;
      } else {
        while (nv--)
          cuckoo[vs[nv+1]] = vs[nv];
        cuckoo[v0] = u0;
      }
    }
    return false;
  }
};
