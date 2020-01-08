'use strict';

const assert = require('assert');
const Miner = require('../bin/miner');

// Use a very low difficulty target
// e.g: 00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
const TARGET = Buffer.concat([Buffer.alloc(1), Buffer.alloc(31, 0xff)]);

const miner = new Miner({
  backend: Miner.BACKEND,
  target: TARGET,
  range: 10000,
  grids: 1000,
  blocks: 10,
  threads: 10000
});

describe('Miner', function() {
  it('should mine a valid block', async () => {
    const job = await miner.getJob();
    const [header, target] = job;

    let nonce = 0, valid = false;
    while (!valid) {
      [nonce, valid] = await miner.mine(header, target);
    }

    assert(valid);

    const hdr = miner.toBlock(header, nonce);

    assert(miner.verify(hdr, TARGET));

    // Avoid zero nonces, to make sure backend is actually grinding on the
    // nonce
    assert(nonce !== 0);
  });
});
