'use strict';

const assert = require('assert');
const crypto = require('crypto');
const miner = require('../');

assert(process.argv.length >= 3);

const hdr = crypto.randomBytes(236);
hdr.fill(0, 216, 236);

console.log('Running stop test for %s.', process.argv[2]);

const job = miner.mineAsync(hdr, {
  backend: process.argv[2],
  nonce: 0,
  range: 0xffffffff,
  target: Buffer.alloc(32, 0x00),
  device: 0
});

job.then(([sol, nonce, match]) => {
  console.log('Stopped with result: %d %s', nonce, match);
}).catch((err) => {
  console.error(err.stack);
  process.exit(1);
});

setTimeout(miner.stopAll, 5000);
