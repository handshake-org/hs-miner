/*!
 * hs-miner.js - hs miner
 * Copyright (c) 2018, Christopher Jeffrey (MIT License).
 * https://github.com/bcoin-org/bcoin
 */

'use strict';

const assert = require('bsert');
const os = require('os');
const binding = require('loady')('hsminer', __dirname);
const miner = exports;

/*
 * Constants
 */

const DIFF = 0x0ffff00000000000000000000000000000000000000000000000000000000000;
const B192 = 0x1000000000000000000000000000000000000000000000000;
const B128 = 0x100000000000000000000000000000000;
const B64 = 0x10000000000000000;
const B0 = 0x1;

/*
 * Miner
 */

miner.mine = function mine(hdr, options) {
  const opt = normalize(options);
  return binding.mine(
    opt.backend,
    hdr,
    opt.nonce,
    opt.range,
    opt.target,
    opt.threads,
    opt.trims,
    opt.device
  );
};

miner.mineAsync = function mineAsync(hdr, options) {
  return new Promise((resolve, reject) => {
    const opt = normalize(options);

    const callback = (err, result) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(result);
    };

    try {
      binding.mineAsync(
        opt.backend,
        hdr,
        opt.nonce,
        opt.range,
        opt.target,
        opt.threads,
        opt.trims,
        opt.device,
        callback
      );
    } catch (e) {
      reject(e);
    }
  });
};

miner.isRunning = binding.isRunning;

miner.stop = binding.stop;

miner.stopAll = binding.stopAll;

miner.verify = function verify(hdr, sol, target) {
  if (!target)
    target = miner.TARGET;
  return binding.verify(hdr, sol, target);
};

miner.blake2b = function blake2b(data, enc) {
  const hash = binding.blake2b(data);
  if (enc === 'hex')
    return hash.toString('hex');
  return hash;
};

miner.sha3 = function sha3(data, enc) {
  const hash = binding.sha3(data);
  if (enc === 'hex')
    return hash.toString('hex');
  return hash;
};

miner.isCUDA = function isCUDA(backend) {
  if (typeof backend !== 'string')
    throw new Error('`backend` must be a string.');

  switch (backend) {
    case 'mean-cuda':
      return true;
    case 'lean-cuda':
      return true;
    default:
      return false;
  }
};

miner.getEdgeBits = binding.getEdgeBits;

miner.getProofSize = binding.getProofSize;

miner.getPerc = binding.getPerc;

miner.getEasiness = binding.getEasiness;

miner.getNetwork = binding.getNetwork;

miner.getBackends = binding.getBackends;

miner.hasBackend = function hasBackend(name) {
  return miner.BACKENDS.indexOf(name) !== -1;
};

miner.hasCUDA = binding.hasCUDA;

miner.hasDevice = binding.hasDevice;

miner.getDeviceCount = binding.getDeviceCount;

miner.getDevices = function getDevices() {
  const raw = binding.getDevices();
  const devices = [];

  for (let i = 0; i < raw.length; i++) {
    const info = raw[i];

    devices.push({
      id: i,
      name: info[0],
      memory: info[1],
      bits: info[2],
      clock: info[3]
    });
  }

  return devices;
};

miner.getCPUCount = function getCPUCount() {
  return os.cpus().length;
};

miner.getCPUs = function getCPUs() {
  const cpus = os.cpus();
  const devices = [];

  for (let i = 0; i < cpus.length; i++) {
    const info = cpus[i];

    devices.push({
      id: i,
      name: info.model,
      memory: os.totalmem(),
      bits: os.arch() === 'x64' ? 64 : 32,
      clock: info.speed * 1024 * 1024
    });
  }

  return devices;
};

miner.getBackend = function getBackend() {
  if (miner.getEdgeBits() >= 28) {
    if (miner.hasCUDA())
      return 'mean-cuda';

    if (getMemory() < 4)
      return 'lean';

    return 'mean';
  }

  if (miner.getEdgeBits() >= 5) {
    if (miner.hasCUDA())
      return 'lean-cuda';

    return 'lean';
  }

  return 'simple';
};

miner.toArray = function toArray(buf) {
  assert(Buffer.isBuffer(buf));
  assert(buf.length !== 0 && (buf.length % 4) === 0);

  const arr = new Uint32Array(buf.length >>> 2);

  let j = 0;

  for (let i = 0; i < arr.length; i++) {
    arr[i] = buf.readUInt32LE(j);
    j += 4;
  }

  return arr;
};

miner.toBuffer = function toBuffer(arr) {
  assert(arr instanceof Uint32Array);
  assert(arr.length !== 0 && (arr.length & 1) === 0);

  const buf = Buffer.allocUnsafe(arr.length << 2);

  let j = 0;

  for (let i = 0; i < arr.length; i++) {
    buf.writeUInt32LE(arr[i], j);
    j += 4;
  }

  return buf;
};

miner.toBits = function toBits(target) {
  assert(Buffer.isBuffer(target));
  assert(target.length === 32);

  let i;

  for (i = 0; i < 32; i++) {
    if (target[i] !== 0)
      break;
  }

  let exponent = 32 - i;

  if (exponent === 0)
    return 0;

  let mantissa = 0;

  if (exponent <= 3) {
    switch (exponent) {
      case 3:
        mantissa |= target[29] << 16;
      case 2:
        mantissa |= target[30] << 8;
      case 1:
        mantissa |= target[31];
    }
    mantissa <<= 8 * (3 - exponent);
  } else {
    const shift = exponent - 3;
    for (; i < 32 - shift; i++) {
      mantissa <<= 8;
      mantissa |= target[i];
    }
  }

  if (mantissa & 0x800000) {
    mantissa >>>= 8;
    exponent += 1;
  }

  const bits = (exponent << 24) | mantissa;

  return bits >>> 0;
};

miner.toTarget = function toTarget(bits) {
  assert((bits >>> 0) === bits);

  if (bits === 0)
    throw new Error('Invalid target.');

  if ((bits >>> 23) & 1)
    throw new Error('Negative target.');

  const exponent = bits >>> 24;

  let mantissa = bits & 0x7fffff;
  let shift;

  if (exponent <= 3) {
    mantissa >>>= 8 * (3 - exponent);
    shift = 0;
  } else {
    shift = (exponent - 3) & 31;
  }

  let i = 31 - shift;

  const target = Buffer.alloc(32, 0x00);

  while (mantissa && i >= 0) {
    target[i--] = mantissa & 0xff;
    mantissa >>>= 8;
  }

  if (mantissa)
    throw new Error('Target overflowed.');

  return target;
};

miner.toDouble = function toDouble(target) {
  assert(Buffer.isBuffer(target));
  assert(target.length === 32);

  let n = 0;
  let hi, lo;

  hi = target.readUInt32BE(0);
  lo = target.readUInt32BE(4);
  n += (hi * 0x100000000 + lo) * B192;

  hi = target.readUInt32BE(8);
  lo = target.readUInt32BE(12);
  n += (hi * 0x100000000 + lo) * B128;

  hi = target.readUInt32BE(16);
  lo = target.readUInt32BE(20);
  n += (hi * 0x100000000 + lo) * B64;

  hi = target.readUInt32BE(24);
  lo = target.readUInt32BE(28);
  n += (hi * 0x100000000 + lo) * B0;

  return n;
};

miner.toDifficulty = function toDifficulty(target) {
  const n = miner.toDouble(target);
  const d = DIFF;

  if (n === 0)
    return d;

  return Math.floor(d / n);
};

miner.toShare = function toShare(hash) {
  return miner.toDifficulty(hash);
};

/*
 * Constants
 */

miner.EDGE_BITS = miner.getEdgeBits();
miner.PROOF_SIZE = miner.getProofSize();
miner.PERC = miner.getPerc();
miner.EASINESS = miner.getEasiness();
miner.NETWORK = miner.getNetwork();
miner.BACKENDS = miner.getBackends();
miner.HAS_CUDA = miner.hasCUDA();
miner.BACKEND = miner.getBackend();
miner.TARGET = Buffer.alloc(32, 0xff);
miner.HDR_SIZE = 164;
miner.NONCE_SIZE = 20;
miner.NONCE_START = 144;
miner.NONCE_END = 160;

/*
 * Helpers
 */

function normalize(options) {
  if (!options)
    options = {};

  if (typeof options === 'string')
    options = { backend: options };

  if (Buffer.isBuffer(options))
    options = { target: options };

  if (typeof options === 'number')
    options = { nonce: options };

  return {
    backend: options.backend || miner.BACKEND,
    nonce: options.nonce || 0,
    range: options.range || 0,
    target: options.target || miner.TARGET,
    threads: options.threads || 0,
    trims: options.trims || 0,
    device: options.device || 0
  };
}

function getMemory() {
  return Math.ceil(os.totalmem() / 1024 / 1024 / 1024);
}
