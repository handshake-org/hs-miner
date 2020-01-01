'use strict';

const assert = require('bsert');
const miner = require('../');
const sha3 = require('./vendor/sha3');
const blake2b = require('./vendor/blake2b');

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

  // Genesis Header (Miner Serialization)
  const header = ''
    // nonce
    + '00000000'
    // time
    + '3f42a45c00000000'
    // padding
    + '0000000000000000000000000000000000000000'
    // prev block
    + '0000000000000000000000000000000000000000000000000000000000000000'
    // tree root
    + '0000000000000000000000000000000000000000000000000000000000000000'
    // commit hash
    + '3a62731564743864425daac90ec4045f40a33379a3ed786ad8ef6ab8992802bb'
    // extra nonce
    + '000000000000000000000000000000000000000000000000'
    // reserved root
    + '0000000000000000000000000000000000000000000000000000000000000000'
    // witness root
    + '7c7c2818c605a97178460aad4890df2afcca962cbcb639b812db0af839949798'
    // merkle root
    + '8e4c9756fef2ad10375f360e0560fcc7587eb5223ddf8cd7c7e06e60a1140b15'
    // version
    + '00000000'
    // bits
    + 'ffff001d';

  it('hash header', () => {
    const input = Buffer.from(header, 'hex');
    const output = miner.hashHeader(input);

    const expect = Buffer.from('d24a10e1cc09aaddb9ca83fd29ffa1b0e8172fba4416e65d54fc71866f51b73f', 'hex');
    assert.bufferEqual(output, expect);
  });
});
