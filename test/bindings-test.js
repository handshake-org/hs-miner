/*!
 * test/bindings-test.js - miner bindings test for hs-miner
 * Copyright (c) 2020, Mark Tyneway (MIT License).
 * https://github.com/handshake-org/hs-miner
 */

'use strict';

const assert = require('bsert');
const miner = require('../');
const sha3 = require('./vendor/sha3');
const blake2b = require('./vendor/blake2b');
const {header} = require('./data/header');
const {powHash} = require('./vendor/powHash');

describe('Bindings', function () {
  it('sha3', () => {
    const input = Buffer.from('00', 'hex');
    const output = miner.sha3(input);
    const expect = sha3.digest(input);
    assert.bufferEqual(output, expect);
  });

  it('blake2b', () => {
    const input = Buffer.from('00', 'hex');
    const output = miner.blake2b(input);
    const expect = blake2b.digest(input, 64);
    assert.bufferEqual(output, expect);
  });

  it('hash header', () => {
    const output = miner.hashHeader(header);
    const expect = powHash(header);
    assert.bufferEqual(output, expect);
  });
});
