'use strict';

const assert = require('bsert');
const Miner = require('../bin/miner');
const {header} = require('./data/header');
const {powHash} = require('./vendor/powHash');

// Use a very low difficulty target
// e.g: 00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
const target = Buffer.concat([
  Buffer.alloc(1, 0x00),
  Buffer.alloc(1, 0x30),
  Buffer.alloc(30, 0x00)
]);

assert(target.length === 32);

const backends = Miner.getBackends();
let miner;

assert(backends.length > 0);

describe('Miner', function() {
  // Run the test suite for each backend
  for (const backend of backends) {
    miner = new Miner({
      backend: backend,
      target: target,
      range: 10000,
      grids: 1000,
      blocks: 10,
      threads: backend === 'simple' ? Miner.getCPUCount() : 10000
    });

    describe(`Backend: ${backend}`, function() {
      it('should mine a valid block', async () => {
        let nonce = 0, valid = false;
        let extraNonce = Buffer.alloc(Miner.EXTRA_NONCE_SIZE);

        while (!valid) {
          [nonce, extraNonce, valid] = await miner.mine(header, target);
        }

        assert(valid);

        const hdr = miner.toBlock(header, nonce, extraNonce);

        // The hash matches the mock Proof of Work algorithm.
        const hash = miner.hashHeader(hdr);
        assert.bufferEqual(hash, powHash(hdr));

        const isvalid = miner.verify(hdr, target);
        assert(isvalid);

        // Avoid zero nonces to make sure the backend
        // is actually grinding on the nonce
        assert(nonce !== 0);
      });
    });
  }
});
