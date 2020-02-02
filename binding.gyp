{
  "variables": {
    "hs_endian%": "<!(bash scripts/get endian)",
    "hs_cudahas%": "<!(bash scripts/get cuda_has)",
    "hs_cudalib%": "<!(bash scripts/get cuda_lib)",
    "hs_network%": "<!(bash scripts/get network)",
    "hs_oclhas%": "<!(bash scripts/get ocl_has)",
    "hs_os%": "<!(bash scripts/get os)"
  },
  "targets": [{
    "target_name": "hsminer",
    "sources": [
      "./src/node/hs-miner.cc",
      "./src/blake2b.c",
      "./src/sha3.c",
      "./src/header.c",
      "./src/verify.cc",
      "./src/opencl.c",
      "./src/simple_unix.cc",
      "./src/simple_windows.cc",
      "./src/utils.c"
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
      "-Wno-cast-function-type",
      "-Wno-unused-parameter",
      "-Wno-unknown-warning-option"
    ],
    "include_dirs": [
      "<!(node -e \"require('nan')\")"
    ],
    "defines": [
      "HS_NETWORK=<(hs_network)",
      "ATOMIC"
    ],
    "conditions": [
      ["hs_endian=='little'", {
        "defines": [
          "HS_LITTLE_ENDIAN"
        ]
      }, {
        "defines": [
          "HS_BIG_ENDIAN"
        ]
      }],
      ["hs_cudahas==1", {
        "defines": [
          "HS_HAS_CUDA"
        ],
        "libraries": [
          "<(module_root_dir)/src/device.a",
          "<(module_root_dir)/src/cuda.a",
          "-L<(hs_cudalib)",
          "-lcudart"
        ]
      }],
      ["hs_oclhas==1", {
        "defines": [
          "HS_HAS_OPENCL"
        ],
        "conditions": [
          ["hs_os=='linux'", {
            "libraries": [
              "-lOpenCL"
            ]
          }],
          ["hs_os=='mac'", {
            "libraries": [
              "-framework OpenCL"
            ]
          }]
        ],
      }]
    ]
  }]
}
