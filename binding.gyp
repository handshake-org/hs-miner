{
  "variables": {
    "hsk_endian%": "<!(./scripts/get endian)",
    "hsk_cudahas%": "<!(./scripts/get cuda_has)",
    "hsk_cudalib%": "<!(./scripts/get cuda_lib)",
    "hsk_edgebits%": "<!(./scripts/get bits)",
    "hsk_proofsize%": "<!(./scripts/get size)",
    "hsk_perc%": "<!(./scripts/get perc)",
    "hsk_network%": "<!(./scripts/get network)"
  },
  "targets": [{
    "target_name": "hskminer",
    "sources": [
      "./src/node/hsk-miner.cc",
      "./src/tromp/blake2b-ref.c",
      "./src/sha3/sha3.c",
      "./src/lean.cc",
      "./src/mean.cc",
      "./src/simple.cc",
      "./src/verify.cc"
    ],
    "cflags": [
      "-Wall",
      "-Wno-implicit-fallthrough",
      "-Wno-uninitialized",
      "-Wno-unused-function",
      "-Wno-unused-value",
      "-Wextra",
      "-O3"
    ],
    "cflags_c": [
      "-std=c99"
    ],
    "cflags_cc+": [
      "-std=c++11",
      "-Wno-maybe-uninitialized",
      "-Wno-cast-function-type"
    ],
    "include_dirs": [
      "<!(node -e \"require('nan')\")"
    ],
    "defines": [
      "HSK_NETWORK=<(hsk_network)",
      "EDGEBITS=<(hsk_edgebits)",
      "PROOFSIZE=<(hsk_proofsize)",
      "PERC=<(hsk_perc)",
      "ATOMIC"
    ],
    "conditions": [
      ["hsk_endian=='little'", {
        "defines": [
          "HSK_LITTLE_ENDIAN"
        ]
      }, {
        "defines": [
          "HSK_BIG_ENDIAN"
        ]
      }],
      ["hsk_cudahas==1", {
        "defines": [
          "HSK_HAS_CUDA"
        ],
        "libraries": [
          "<(module_root_dir)/src/device.a",
          "<(module_root_dir)/src/mean-cuda.a",
          "<(module_root_dir)/src/lean-cuda.a",
          "-L<(hsk_cudalib)",
          "-lcudart"
        ]
      }]
    ]
  }]
}
