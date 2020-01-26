# hs-miner

CUDA and OpenCL capable POW miner for Handshake.

## Usage

Simply point the miner at an HS RPC server and you're off.

``` js
$ hs-miner --rpc-host localhost --rpc-port 13037 --rpc-pass my-password
```

## CLI Usage

Another small utility is available for mining arbitrary headers. This
is most useful for testing.

``` js
# Mine a single block
$ hs-mine [header-hex] [target] [backend] -n [nonce] -r [range]
```

## API Usage

``` js
const miner = require('hs-miner');

const hdr = Buffer.alloc(256, 0x00);

if (miner.hasCUDA())
  console.log('Mining with cuda support!');

console.log('CUDA devices:');
console.log(miner.getDevices());

(async () => {
  const [nonce, match] = await miner.mineAsync(hdr, {
    backend: 'cuda',
    target: Buffer.alloc(32, 0xff),
    grids: 256,
    blocks: 8,
    threads: 2048
  });

  console.log('Nonce: %d', nonce);
  console.log('Match: %s', match);
})();
```

## API

### Functions

- `miner.mine(hdr, options)` - Mine a to-be-solved header (sync).
- `miner.mineAsync(hdr, options)` - Mine a to-be-solved header (async).
- `miner.isRunning(device)` - Test whether a device is currently running.
- `miner.stop(device)` - Stop a running job.
- `miner.stopAll()` - Stop all running jobs.
- `miner.verify(hdr, target?)` - Verify a to-be-solved header (sync).
- `miner.blake2b(data, enc)` - Hash a piece of data with blake2b.
- `miner.sha3(data, enc)` - Hash a piece of data with sha3.
- `miner.hashHeader(data, enc)` - Hash a piece of data with pow hash.
- `miner.isCUDA(backend)` - Test whether a backend is a CUDA backend.
- `miner.getNetwork()` - Get network (compile time flag).
- `miner.getBackends()` - Get available backends.
- `miner.hasCUDA()` - Test whether CUDA support was built.
- `miner.hasOpenCL()` - Test whether OpenCL support was built.
- `miner.hasDevice()` - Test whether a device is available.
- `miner.getCUDADeviceCount()` - Get count of CUDA devices.
- `miner.getOpenCLDeviceCount()` - Get count of OpenCL devices.
- `miner.getCUDADevices()` - Get CUDA devices. Returns an array of objects.
- `miner.getOpenCLDevices()` - Get OpenCL devices. Returns an array of objects.

## Utilities

- `miner.toBits(target)` - Convert a big endian target to a mantissa.
- `miner.toTarget(bits)` - Convert mantissa to big endian target.
- `miner.toDouble(target)` - Convert a big endian target to a double.
- `miner.toDifficulty(target)` - Convert target/hash to a difficulty/share.
- `miner.toShare(hash)` - Alias of `toDifficulty`.

### Constants

- `miner.NETWORK` - Network (compile time flag).
- `miner.BACKENDS` - Available backends.
- `miner.HAS_CUDA` - Whether CUDA support was built.
- `miner.BACKEND` - Default backend.
- `miner.TARGET` - Default target.
- `miner.HDR_SIZE` - Handshake to-be-solved header size (256).
- `miner.EXTRA_NONCE_START` - Start of nonce position (128).
- `miner.EXTRA_NONCE_END` - End of extra nonce position (152).

## Options

- `backend` - Name of the desired backend.
- `range` - How many iterations before the miner stops looking.
- `nonce` - 32 bit nonce to start mining from.
- `target` - Big-endian target (32 bytes).
- `grids` - Backend-specific, see below.
- `blocks` - Backend-specific, see below.
- `threads` - Backend-specific, see below.

## Backends (so far)

- CUDA - POW miner with CUDA (`cuda.cu`).
- OpenCL - POW miner with OpenCL (`pow-ng.cl`).
- CPU - Simple miner, mostly for testing (`simple.cc`).

## Platform Support

The code has only been tested on Linux. Realistically, linux is the only thing
that should matter for mining, but build support for other OSes is welcome via
pull request.

Supports 64bit only right now.

## Todo

- Stratum support.

## Notes

When using one of the CUDA backends, only one job per device is allowed at a
time. This is done because the CUDA miners generally wipe out your GPU's memory
anyway.

The `grids`, `blocks` and `threads` parameters are backend-specific. You may have to dig into each to
figure out what reasonable values are and how they work.

For CUDA support, CUDA must be installed in either `/opt/cuda` or
`/usr/local/cuda` when running the build scripts.

This can be modified with the `CUDA_PREFIX` environment variable:

``` bash
$ CUDA_PREFIX=/path/to/cuda ./scripts/rebuild
```

## Installation

NodeJS installation guide:
https://nodejs.org/en/download/package-manager/

If you're on an OS without native NVIDIA packages, drivers can be installed
from: https://www.nvidia.com/Download/Find.aspx

CUDA is available from NVIDIA's download page:
https://developer.nvidia.com/cuda-downloads

### Debian & Ubuntu

``` bash
$ sudo apt-get install linux-headers-$(uname -r)
$ sudo apt-get install build-essential

# Install latest NVIDIA drivers
$ sudo add-apt-repository ppa:graphics-drivers/ppa
$ sudo apt update
$ sudo apt install nvidia-390

# Install CUDA
# Pick out your installation: https://developer.nvidia.com/cuda-downloads
$ wget http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1704/x86_64/cuda-repo-ubuntu1704_9.1.85-1_amd64.deb
$ sudo dpkg -i cuda-repo-ubuntu1704_9.1.85-1_amd64.deb
$ sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1704/x86_64/7fa2af80.pub
$ sudo apt-get update
$ sudo apt-get install cuda

# Install the latest node.js
$ curl -sL https://deb.nodesource.com/setup_9.x | sudo -E bash -
$ sudo apt-get install nodejs

# Install git & python
$ sudo apt-get install git python

$ npm install hs-miner
```

### RHEL & Fedora

Follow this installation guide for nvidia drivers:
https://www.if-not-true-then-false.com/2015/fedora-nvidia-guide/

This also looks promising:
https://negativo17.org/nvidia-driver/

#### Install CUDA (RHEL)

``` bash
# Pick out your installation: https://developer.nvidia.com/cuda-downloads
$ wget http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-repo-rhel7-9.1.85-1.x86_64.rpm
$ sudo rpm -i cuda-repo-rhel7-9.1.85-1.x86_64.rpm
$ sudo yum clean all
$ sudo yum install cuda
```

#### Install CUDA (Fedora)

``` bash
# Pick out your installation: https://developer.nvidia.com/cuda-downloads
$ wget http://developer.download.nvidia.com/compute/cuda/repos/fedora25/x86_64/cuda-repo-fedora25-9.1.85-1.x86_64.rpm
$ sudo rpm -i cuda-repo-fedora25-9.1.85-1.x86_64.rpm
$ sudo dnf clean all
$ sudo dnf install cuda
```

#### Install node.js & hs-miner (Both)

``` bash
$ curl --silent --location https://rpm.nodesource.com/setup_9.x | sudo bash -
$ sudo yum install nodejs gcc-c++ make git python2
$ npm install hs-miner
```

### Arch Linux

``` bash
$ sudo pacman -S nodejs npm git nvidia nvidia-utils nvidia-settings cuda python2
$ npm install hs-miner
```

### OSX

``` bash
$ brew install node git coreutils perl grep gnu-sed gawk python2
$ brew tap caskroom/drivers
$ brew cask install nvidia-cuda
$ npm install hs-miner
```

### Windows

TODO

## Debugging

Pass an extra argument to the `make` commands to specify special behavior.
Run `make regtest extra=preprocess` to output `.cup` files for the CUDA files.
Or pass an environment variable `EXTRA_ARG` to one of the npm `install-*`
scripts for the same behavior, such as `$ EXTRA_ARG=preprocess npm run install`.

## Contribution and License Agreement

If you contribute code to this project, you are implicitly allowing your code
to be distributed under the MIT license. You are also implicitly verifying that
all code is your original work. `</legalese>`

## License

- Copyright (c) 2018, Christopher Jeffrey (MIT License).

See LICENSE for more info.
