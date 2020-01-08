/**
 * test/vendor/powHash.js
 * Copyright (c) 2020, Mark Tyneway (MIT)
 * https://github.com/handshake-org/hs-miner
 */

'use strict'

const assert = require('bsert');
const blake2b = require('./blake2b');
const sha3 = require('./sha3');

exports.powHash = function powHash(header) {
  assert(Buffer.isBuffer(header));
  assert(header.length === 256);

  const padding = exports.padHeader(header);

  const preheader = header.slice(0, 128);

  const left = blake2b.digest(preheader, 64);
  const right = sha3.multi(preheader, padding.slice(0, 8));
  const hash = blake2b.multi(left, padding.slice(), right);

  return hash;
}

exports.padHeader = function padHeader(header) {
  assert(header.length === 256);
  const prevBlock = header.slice(32, 64);
  const treeRoot = header.slice(64, 96);

  const padding = Buffer.alloc(32);

  for (let i = 0; i < 32; i++)
    padding[i] = prevBlock[i % 32] ^ treeRoot[i % 32];

  return padding;
}
