'use strict';

const assert = require('assert');
const request = require('brq');
const miner = require('../');

class Miner {
  constructor(options) {
    this.backend = options.backend || miner.BACKEND;
    this.range = options.range || 0;
    this.grids = options.grids || 0;
    this.blocks = options.blocks || 0;
    this.threads = options.threads || 0;
    this.device = options.device == null ? -1 : options.device;
    this.ssl = options.ssl || false;
    this.host = options.host || 'localhost';
    this.port = options.port || getPort();
    this.user = options.user || 'hnsrpc';
    this.pass = options.pass || '';
    this.count = 1;
    this.sequence = 0;
    this.hdr = Buffer.alloc(miner.HDR_SIZE, 0x00);
    this.target = options.target || Buffer.alloc(32, 0xff);
    this.height = 0;
    this.mining = false;
    this.offset = 0;
    this.root = Buffer.alloc(32, 0x00).toString('hex');

    if (miner.HAS_CUDA)
      this.count = miner.getDeviceCount();
  }

  log(...args) {
    console.log(...args);
  }

  error(...args) {
    console.error(...args);
  }

  start() {
    if (!miner.hasBackend(this.backend))
      throw new Error(`Backend ${this.backend} not supported!`);

    this.log('Miner params:');
    this.log('  Backend: %s', this.backend);
    this.log('  CUDA: %s', miner.HAS_CUDA);
    this.log('  Network: %s', miner.NETWORK);
    this.log('');

    if (miner.HAS_CUDA) {
      this.log('CUDA Devices:');
      for (const {id, name, memory, bits, clock} of miner.getDevices())
        this.log(`  ${id}: <${name}> ${memory} ${bits} ${clock}`);
    } else {
      this.log('CPUs:');
      for (const {id, name, memory, bits, clock} of miner.getCPUs())
        this.log(`  ${id}: <${name}> ${memory} ${bits} ${clock}`);
    }

    this.log('');
    this.log('Starting miner...');

    this.timer = setInterval(() => this.poll(), 3000);
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
    this.mining = false;
  }

  now() {
    return Math.floor(Date.now() / 1000) + this.offset;
  }

  async poll() {
    try {
      await this.repoll();
    } catch (e) {
      this.error(e.stack);
    }
  }

  async repoll() {
    const result = await this.getWork(this.root);

    if (!result)
      return;

    const {
      hdr,
      target,
      height,
      time,
      root
    } = result;

    const now = Math.floor(Date.now() / 1000);
    const offset = time - now;

    if (offset !== this.offset) {
      this.offset = offset;
      this.log('Time offset: %d', this.offset);
    }

    this.hdr = hdr;
    this.target = target;
    this.height = height;
    this.root = root;

    miner.stopAll();

    this.log('New job: %d', height);
    this.log('New target: %s', target.toString('hex'));
    this.log(readJSON(hdr));

    if (!this.mining) {
      this.mining = true;
      this.work();
    }
  }

  async getWork(root) {
    const res = await this.execute('getwork', [root]);

    if (!res)
      return null;

    if (typeof res !== 'object')
      throw new Error('Non-object sent as getwork response.');

    if (res.network !== miner.NETWORK) {
      console.error('Wrong network: %s.', res.network);
      process.exit(1);
    }

    if (res.data.length !== miner.HDR_SIZE * 2)
      throw new Error('Bad header size.');

    const hdr = Buffer.from(res.data, 'hex');

    if (hdr.length !== miner.HDR_SIZE)
      throw new Error('Bad header size.');

    if (res.target.length !== 64)
      throw new Error('Bad target size.');

    const target = Buffer.from(res.target, 'hex');

    if (target.length !== 32)
      throw new Error('Bad target size.');

    const height = res.height;

    if ((height >>> 0) !== height)
      throw new Error('Bad height.');

    const time = res.time;

    if ((time >>> 0) !== time)
      throw new Error('Bad time.');

    const {merkleRoot} = readHeader(hdr);

    return {
      hdr,
      target,
      height,
      time,
      root: merkleRoot
    };
  }

  async submitWork(hdr) {
    this.log('Submitting work:');
    this.log(readJSON(hdr));

    const res = await this.execute('submitwork', [hdr.toString('hex')]);

    if (!Array.isArray(res))
      throw new Error('Non-array sent as submitwork response.');

    if (typeof res[0] !== 'boolean')
      throw new Error('Non-boolean sent as submitwork response.');

    if (typeof res[1] !== 'string')
      throw new Error('Non-string sent as submitwork response.');

    return res;
  }

  toBlock(hdr, nonce) {
    assert(hdr.length === miner.HDR_SIZE);
    hdr.writeUInt32LE(nonce, 0, 4);
    return hdr;
  }

  job(index, hdr, target) {
    return miner.mineAsync(hdr, {
      backend: this.backend,
      nonce: index * this.range,
      range: this.range,
      target,
      grids: this.grids,
      blocks: this.blocks,
      threads: this.threads,
      device: index
    });
  }

  async mine(hdr, target) {
    const jobs = [];

    if (this.device !== -1) {
      this.log('Using device: %d', this.device);
      jobs.push(this.job(this.device, hdr, target));
    } else {
      for (let i = 0; i < this.count; i++)
        jobs.push(this.job(i, hdr, target));
    }

    const result = await Promise.all(jobs);

    for (let i = 0; i < result.length; i++) {
      const [nonce, match] = result[i];

      if (match)
        return [nonce, true];
    }

    return [0, false];
  }

  getJob() {
    return [this.hdr, this.target, this.height, this.root];
  }

  async work() {
    try {
      await this._work();
    } catch (e) {
      this.error(e.stack);
    }
  }

  async _work() {
    let nonce;
    let valid;
    let i = 0;

    for (;;) {
      if (!this.mining)
        break;

      // Handle overflow
      i = i++ % 1000;
      const [hdr, target, height, root] = this.getJob();

      increment(hdr, this.now());

      if (i % 1e2 === 0) {
        this.log('Mining height %d (target=%s).',
          height, target.toString('hex'));
      }

      try {
        [nonce, valid] = await this.mine(hdr, target);
      } catch (e) {
        this.error(e.stack);
        continue;
      }

      if (!valid)
        continue;

      if (root !== this.root) {
        this.log('New job. Switching.');
        continue;
      }

      this.log('Found valid nonce: %d', nonce);

      const raw = this.toBlock(hdr, nonce);

      let reason = '';

      try {
        [valid, reason] = await this.submitWork(raw);
      } catch (e) {
        this.error(e.stack);
      }

      if (!valid) {
        this.log('Invalid block submitted: %s.', miner.blake2b(raw, 'hex'));
        this.log('Reason: %s', reason);
      }

      if (root !== this.root) {
        this.log('New job. Switching.');
        continue;
      }

      await this.poll();
    }
  }

  async execute(method, params) {
    assert(typeof method === 'string');

    if (params == null)
      params = null;

    this.sequence += 1;

    const res = await request({
      method: 'POST',
      ssl: this.ssl,
      host: this.host,
      port: this.port,
      path: '/',
      username: this.user,
      password: this.pass,
      pool: true,
      json: {
        method: method,
        params: params,
        id: this.sequence
      }
    });

    if (res.statusCode === 401)
      throw new Error('Unauthorized (bad API key).');

    if (res.type !== 'json')
      throw new Error('Bad response (wrong content-type).');

    const json = res.json();

    if (!json)
      throw new Error('No body for JSON-RPC response.');

    if (json.error) {
      const {message, code} = json.error;
      throw new Error([message, code].join(' '));
    }

    if (res.statusCode !== 200)
      throw new Error(`Status code: ${res.statusCode}.`);

    return json.result;
  }

  hashHeader(header) {
    return miner.hashHeader(header);
  }

  verify(header, target) {
    return miner.verify(header, target);
  }
}

/*
 * Helpers
 */

function increment(hdr, now) {
  const time = readTime(hdr, 132);

  switch (miner.NETWORK) {
    case 'main':
    case 'regtest':
      if (now > time) {
        writeTime(hdr, now, 132);
        return;
      }
      break;
  }

  // Increment the extra nonce.
  // TODO: increment part of the extra nonce and
  // add randomness to part of the extra nonce
  // so that this software can run in parallel and
  // search different nonce spaces.
  for (let i = miner.NONCE_START; i < miner.NONCE_END; i++) {
    if (hdr[i] !== 0xff) {
      hdr[i] += 1;
      break;
    }
    hdr[i] = 0;
  }
}

function readTime(hdr, off) {
  assert(hdr.length >= off + 8);

  const lo = hdr.readUInt32LE(off);
  const hi = hdr.readUInt16LE(off + 4);

  assert(hdr.readUInt16LE(off + 6) === 0);

  return hi * 0x100000000 + lo;
}

function writeTime(hdr, time, off) {
  assert(hdr.length >= off + 8);
  assert(time >= 0 && time <= 0xffffffffffff);

  const lo = time >>> 0;
  const hi = (time * (1 / 0x100000000)) >>> 0;

  hdr.writeUInt32LE(lo, off);
  hdr.writeUInt16LE(hi, off + 4);
  hdr.writeUInt16LE(0, off + 6);
}

function readHeader(hdr) {
  return {
    nonce: hdr.readUInt32LE(0),
    time: readTime(hdr, 4),
    padding: hdr.toString('hex', 12, 32),
    prevBlock: hdr.toString('hex', 32, 64),
    treeRoot: hdr.toString('hex', 64, 96),
    maskHash: hdr.toString('hex', 96, 128),
    extraNonce: hdr.toString('hex', 128, 152),
    reservedRoot: hdr.toString('hex', 152, 184),
    witnessRoot: hdr.toString('hex', 184, 216),
    merkleRoot: hdr.toString('hex', 216, 248),
    version: hdr.readUInt32LE(248),
    bits: hdr.readUInt32LE(252)
  };
}

function readJSON(hdr) {
  return JSON.stringify(readHeader(hdr), null, 2);
}

function getPort() {
  switch (miner.NETWORK) {
    case 'main':
      return 12037;
    case 'testnet':
      return 13037;
    case 'regtest':
      return 14037;
    case 'simnet':
      return 15037;
    default:
      return 12037;
  }
}

/*
 * Expose
 */

module.exports = Miner;
