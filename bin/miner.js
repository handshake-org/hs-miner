'use strict';

const assert = require('assert');
const request = require('brq');
const miner = require('../');

class Miner {
  constructor(options) {
    this.backend = options.backend || miner.BACKEND;
    this.range = options.range || 0;
    this.threads = options.threads || 0;
    this.trims = options.trims || 0;
    this.device = options.device == null ? -1 : options.device;
    this.ssl = options.ssl || false;
    this.host = options.host || 'localhost';
    this.port = options.port || getPort();
    this.user = options.user || 'hsrpc';
    this.pass = options.pass || '';
    this.count = 1;
    this.sequence = 0;
    this.hdr = Buffer.alloc(miner.HDR_SIZE, 0x00);
    this.target = Buffer.alloc(32, 0xff);
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
    this.log('  Edge Bits: %d', miner.EDGE_BITS);
    this.log('  Proof Size: %d', miner.PROOF_SIZE);
    this.log('  Easipct: %d', miner.PERC);
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

  toBlock(hdr, nonce, sol) {
    assert(hdr.length === miner.HDR_SIZE);
    const raw = Buffer.allocUnsafe(hdr.length + 1 + sol.length);
    hdr.copy(raw, 0);
    raw.writeUInt32LE(nonce >>> 0, hdr.length - 4);
    raw[hdr.length] = sol.length >>> 2;
    sol.copy(raw, hdr.length + 1);
    return raw;
  }

  job(index, hdr, target) {
    return miner.mineAsync(hdr, {
      backend: this.backend,
      nonce: index * this.range,
      range: this.range,
      target,
      threads: this.threads,
      trims: this.trims,
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
      const [sol, nonce, match] = result[i];

      if (match)
        return [sol, nonce];

      if (sol) {
        const hash = miner.sha3(sol, 'hex');
        this.log('Best share: %s with %d (device=%d)', hash, nonce, i);
      }
    }

    return [null, 0];
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
    let sol = null;
    let nonce;

    for (;;) {
      if (!this.mining)
        break;

      const [hdr, target, height, root] = this.getJob();

      increment(hdr, this.now());

      this.log('Mining height %d (target=%s).',
        height, target.toString('hex'));

      try {
        [sol, nonce] = await this.mine(hdr, target);
      } catch (e) {
        this.error(e.stack);
        continue;
      }

      if (root !== this.root) {
        this.log('New job. Switching.');
        continue;
      }

      if (!sol) {
        increment(hdr, this.now());
        continue;
      }

      this.log('Found solution: %d %s',
        nonce, miner.sha3(sol).toString('hex'));

      const raw = this.toBlock(hdr, nonce, sol);

      let valid = true;
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
  let hash = undefined;
  let solution = undefined;
  let powHash = undefined;

  if (hdr.length > miner.HDR_SIZE) {
    const size = hdr[miner.HDR_SIZE] * 4;
    assert(size === miner.PROOF_SIZE * 4);

    const off = miner.HDR_SIZE + 1;

    assert(hdr.length === off + size);

    hash = miner.blake2b(hdr, 'hex');
    solution = hdr.slice(off, off + size);
    powHash = miner.sha3(solution, 'hex');

    solution = solution.toString('hex');
  } else {
    assert(hdr.length === miner.HDR_SIZE);
  }

  return {
    hash,
    powHash,
    version: hdr.readUInt32LE(0),
    prevBlock: hdr.toString('hex', 4, 36),
    merkleRoot: hdr.toString('hex', 36, 68),
    treeRoot: hdr.toString('hex', 68, 100),
    reservedRoot: hdr.toString('hex', 100, 132),
    time: readTime(hdr, 132),
    bits: hdr.readUInt32LE(140),
    nonce: hdr.toString('hex', miner.NONCE_START, miner.HDR_SIZE),
    solution
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
