'use strict';

const assert = require('assert');
const Miner = require('../bin/miner');

const miner = new Miner({
  backend: Miner.BACKEND,
  target: Miner.TARGET,
  threads: 16
});

describe('Miner', function() {
  it('should mine a valid block', async () => {
    const job = await miner.getJob();
    const [header, target] = job;

    const [nonce, valid] = await miner.mine(header, target);

    assert(valid);

    const hdr = miner.toBlock(header, nonce);

    assert(miner.verify(hdr, Miner.TARGET));
  });
});
