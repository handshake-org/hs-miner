#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#define H_HEADER_SIZE 192
#define KERNEL_FILE "./src/pow-ng.cl"
#define KERNEL_FUNC "pow_ng"

#include <stdio.h>
#include "common.h"
#include "error.h"
#include "header.h"

#ifdef HS_HAS_OPENCL

/**
 * OpenCL headers are different for Apple.
 */
#ifdef __APPLE__
#include <OpenCL/opencl.h>
#else
#include <CL/cl.h>
#endif /* __APPLE__ */

static inline void
commit_hash(
  const uint8_t *sub_header,
  const uint8_t *mask_hash,
  uint8_t *commit_hash
) {
  uint8_t sub_hash[32];

  /**
   * Create the sub_hash by hashing the
   * sub_header with blake2b-256.
   */
  hs_blake2b_ctx ctx;
  hs_blake2b_init(&ctx, 32);
  hs_blake2b_update(&ctx, sub_header, 128);
  hs_blake2b_final(&ctx, sub_hash, 32);

  /**
   * Create the commit_hash by hashing together the
   * sub_hash and the mask_hash with blake2b-256.
   * The mask_hash is included in the miner header
   * serialization that comes from `getwork` or stratum.
   */
  hs_blake2b_init(&ctx, 32);
  hs_blake2b_update(&ctx, sub_hash, 32);
  hs_blake2b_update(&ctx, mask_hash, 32);
  hs_blake2b_final(&ctx, commit_hash, 32);
}

static inline void
padding(
  const uint8_t *prev_block,
  const uint8_t *tree_root,
  uint8_t *padding,
  size_t len
) {
  uint8_t p[32];

  for (size_t i = 0; i < len; i++)
    p[i] = prev_block[i % 32] ^ tree_root[i % 32];

  memcpy(padding, p, len);
}

int32_t
hs_opencl_run(
  hs_options_t *options,
  uint32_t *result,
  uint8_t *extra_nonce,
  bool *match
) {
  cl_int err;
  cl_platform_id pid;
  cl_device_id *dids;
  cl_uint count;
  cl_context ctx;
  cl_program clp;
  cl_command_queue queue;
  cl_kernel kernel;

  /**
   * Identify platform.
   *
   * Note: this function call will only
   * detect the first platform found.
   */
  err = clGetPlatformIDs(1, &pid, NULL);
  if (err != CL_SUCCESS) {
    printf("failed to identify a platform: %d\n", err);
    exit(1);
  }

  /* Access devices. */
  err = clGetDeviceIDs(pid, CL_DEVICE_TYPE_GPU, 0, NULL, &count);
  if (err != CL_SUCCESS) {
    printf("failed to access any devices: %d\n", err);
    exit(1);
  }

  dids = (cl_device_id *)malloc(sizeof(cl_device_id) * count);
  err = clGetDeviceIDs(pid, CL_DEVICE_TYPE_GPU, count, dids, NULL);
  if (err != CL_SUCCESS) {
    printf("failed to access any devices: %d\n", err);
    free(dids);
    exit(1);
  }

  /* Create context. */
  ctx = clCreateContext(NULL, count, dids, NULL, NULL, &err);
  if(err != CL_SUCCESS) {
    printf("failed to create a context: %d\n", err);
    free(dids);
    exit(1);
  }

  /* Read kernel file. */
  FILE *fp = fopen(KERNEL_FILE, "r");
  if(fp == NULL) {
    printf("failed to find the program file: %s\n", KERNEL_FILE);
    free(dids);
    exit(1);
  }

  /* Get size in bytes. */
  fseek(fp, 0, SEEK_END);
  size_t sz = ftell(fp);
  rewind(fp);

  /* Read bytes into buffer. */
  char *buf = (char*)malloc(sz + 1);
  buf[sz] = '\0';
  if (fread(buf, sizeof(char), sz, fp) != sz) {
    printf("failed to read the program file: %s\n", KERNEL_FILE);
    free(dids);
    free(buf);
    exit(1);
  }
  fclose(fp);

  /* Create program from buffer. */
  clp = clCreateProgramWithSource(ctx, 1, (const char**)&buf, &sz, &err);
  if(err != CL_SUCCESS) {
    printf("failed to create the program: %d\n", err);
    free(dids);
    free(buf);
    exit(1);
  }

  free(buf);

  /* Build program. */
  err = clBuildProgram(clp, 0, NULL, NULL, NULL, NULL);
  if(err != CL_SUCCESS) {
    clGetProgramBuildInfo(clp, dids[options->device], CL_PROGRAM_BUILD_LOG,
      0, NULL, &sz);

    char *log = (char*)malloc(sz + 1);
    log[sz] = '\0';

    clGetProgramBuildInfo(clp, dids[options->device], CL_PROGRAM_BUILD_LOG,
      sz + 1, log, NULL);

    printf("%s\n", log);
    free(dids);
    free(log);
    exit(1);
  }

  /**
   * h_header serialization:
   *
   * nonce:        4 bytes
   * timestamp:    8 bytes
   * padding:     20 bytes
   * prev_block:  32 bytes
   * tree_root:   32 bytes
   * commit hash: 32 bytes
   * padding:     32 bytes
   * target:      32 bytes
   */
  uint8_t h_header[H_HEADER_SIZE];
  memcpy(h_header, options->header, 96);
  commit_hash(options->header + 128, options->header + 96, h_header + 96);
  padding(options->header + 32, options->header + 64, h_header + 128, 32);
  memcpy(h_header + 160, options->target, 32);

  /* Create on-device memory buffers. */
  cl_mem d_header = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_ALLOC_HOST_PTR
      | CL_MEM_COPY_HOST_PTR, H_HEADER_SIZE, h_header, &err);

  if (err != CL_SUCCESS) {
    printf("failed to create d_header buffer: %d\n", err);
    free(dids);
    exit(1);
  }

  cl_mem d_nonce = clCreateBuffer(ctx, CL_MEM_WRITE_ONLY |
    CL_MEM_ALLOC_HOST_PTR, sizeof(uint32_t), NULL, &err);

  if (err != CL_SUCCESS) {
    printf("failed to create d_nonce buffer: %d\n", err);
    free(dids);
    exit(1);
  }

  cl_mem d_start_nonce = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_ALLOC_HOST_PTR
    | CL_MEM_COPY_HOST_PTR, sizeof(uint32_t), &options->nonce, &err);

  if (err != CL_SUCCESS) {
    printf("failed to create d_start_nonce buffer: %d\n", err);
    free(dids);
    exit(1);
  }

  cl_mem d_range = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_ALLOC_HOST_PTR
    | CL_MEM_COPY_HOST_PTR, sizeof(uint32_t), &options->range, &err);

  if (err != CL_SUCCESS) {
    printf("failed to create d_range buffer: %d\n", err);
    free(dids);
    exit(1);
  }

  cl_mem d_match = clCreateBuffer(ctx, CL_MEM_WRITE_ONLY | CL_MEM_ALLOC_HOST_PTR
    | CL_MEM_COPY_HOST_PTR, sizeof(bool), match, &err);

  if (err != CL_SUCCESS) {
    printf("failed to create d_match buffer: %d\n", err);
    free(dids);
    exit(1);
  }

  /* Create a command queue. */
  queue = clCreateCommandQueue(ctx, dids[options->device], 0, &err);
  if(err != CL_SUCCESS) {
    printf("failed to create a command queue: %d\n", err);
    free(dids);
    exit(1);
  };

  /* Query the max work group size. */
  size_t max_wg_size = 0;
  err = clGetDeviceInfo(dids[options->device], CL_DEVICE_MAX_WORK_GROUP_SIZE,
    sizeof(size_t), &max_wg_size, NULL);

  if (err != CL_SUCCESS) {
    printf("failed to get CL_DEVICE_MAX_WORK_GROUP_SIZE: %d\n", err);
    free(dids);
    exit(1);
  }

  /* Query the max work item dimensions. */
  size_t max_wi_dim;
  err = clGetDeviceInfo(dids[options->device],
    CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS, sizeof(max_wi_dim), &max_wi_dim, NULL);

  if (err != CL_SUCCESS) {
    printf("failed to get CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS: %d\n", err);
    free(dids);
    exit(1);
  }

  /* Query the max work item size for each dimension. */
  size_t *max_wi_size = (size_t *)malloc(sizeof(size_t) * max_wi_dim);
  err = clGetDeviceInfo(dids[options->device], CL_DEVICE_MAX_WORK_ITEM_SIZES,
    sizeof(size_t) * max_wi_dim, max_wi_size, NULL);

  if (err != CL_SUCCESS) {
    printf("failed to get CL_DEVICE_MAX_WORK_ITEM_SIZES: %d\n", err);
    free(max_wi_size);
    free(dids);
    exit(1);
  }

  /* Calculate the max work items for the device. */
  size_t max_work_items = 1;
  for (size_t i = 0; i < max_wi_dim; i++)
    max_work_items *= max_wi_size[i];

  free(max_wi_size);
  free(dids);

  /* Create a kernel. */
  kernel = clCreateKernel(clp, KERNEL_FUNC, &err);
  if(err != CL_SUCCESS) {
    printf("failed create a kernel: %d\n", err);
    exit(1);
  };

  /* Create kernel arguments. */
  err = clSetKernelArg(kernel, 0, sizeof(cl_mem), &d_header);
  err |= clSetKernelArg(kernel, 1, sizeof(cl_mem), &d_nonce);
  err |= clSetKernelArg(kernel, 2, sizeof(cl_mem), &d_start_nonce);
  err |= clSetKernelArg(kernel, 3, sizeof(cl_mem), &d_range);
  err |= clSetKernelArg(kernel, 4, sizeof(cl_mem), &d_match);
  if(err != CL_SUCCESS) {
    printf("failed to create kernel arguments: %d\n", err);
    exit(1);
  }

  size_t total_work_items = options->threads;
  size_t work_group_size = options->blocks;

  if (total_work_items > max_work_items || total_work_items < 1)
    total_work_items = max_work_items;

  if (work_group_size > max_wg_size || work_group_size < 1)
    work_group_size = max_wg_size;

  /**
   * If total_work_items is not divisible by work_group_size,
   * we need to lower total_work_items to the next multiple
   * of work_group_size.
   */
  if (total_work_items % work_group_size != 0)
    total_work_items = total_work_items / work_group_size * work_group_size;

  printf("Total work items: %lu\n", total_work_items);
  printf("Work group size: %lu\n", work_group_size);

  /* Enqueue kernel. */
  err = clEnqueueNDRangeKernel(queue, kernel, 1, NULL,
    &total_work_items, &work_group_size, 0, NULL, NULL);

  if (err != CL_SUCCESS) {
    printf("failed to enqueue the kernel: %d\n", err);
    exit(1);
  }

  /* Read kernel output. */
  err = clEnqueueReadBuffer(queue, d_nonce, CL_TRUE, 0,
    sizeof(uint32_t), result, 0, NULL, NULL);

  if (err != CL_SUCCESS) {
    printf("failed to read the buffer: %d\n", err);
    exit(1);
  }

  err = clEnqueueReadBuffer(queue, d_match, CL_TRUE, 0,
    sizeof(bool), match, 0, NULL, NULL);

  if (err != CL_SUCCESS) {
    printf("failed to read the buffer: %d\n", err);
    exit(1);
  }

  /* Deallocate resources. */
  clReleaseKernel(kernel);
  clReleaseMemObject(d_header);
  clReleaseMemObject(d_nonce);
  clReleaseMemObject(d_start_nonce);
  clReleaseMemObject(d_range);
  clReleaseMemObject(d_match);
  clReleaseCommandQueue(queue);
  clReleaseProgram(clp);
  clReleaseContext(ctx);

  if (*match)
    return HS_SUCCESS;

  return HS_ENOSOLUTION;
}

uint32_t
hs_opencl_device_count() {
  cl_uint p_count, d_count;
  cl_platform_id *pids;
  cl_uint total = 0;
  cl_int err;

  err = clGetPlatformIDs(0, NULL, &p_count);
  if (err != CL_SUCCESS || !p_count) {
    printf("failed to retrieve platform count: %d\n", err);
    exit(1);
  }

  pids = (cl_platform_id *)malloc(sizeof(cl_platform_id) * p_count);
  err = clGetPlatformIDs(p_count, pids, NULL);
  if (err != CL_SUCCESS) {
    printf("failed to retreive platform ids: %d\n", err);
    free(pids);
    exit(1);
  }

  for (cl_uint i = 0; i < p_count; i++) {
    err = clGetDeviceIDs(pids[i], CL_DEVICE_TYPE_GPU, 0, NULL, &d_count);
    if (err != CL_SUCCESS)
      continue;
    total += d_count;
  }

  free(pids);
  return total;
}

bool
hs_opencl_device_info(uint32_t device, hs_device_info_t *info) {
  cl_uint p_count, d_count;
  cl_platform_id *pids;
  cl_device_id *dids;
  cl_uint total = 0;
  cl_int err;

  err = clGetPlatformIDs(0, NULL, &p_count);
  if (err != CL_SUCCESS || !p_count) {
    printf("failed to retrieve platform count: %d\n", err);
    exit(1);
  }

  pids = (cl_platform_id *)malloc(sizeof(cl_platform_id) * p_count);
  err = clGetPlatformIDs(p_count, pids, NULL);
  if (err != CL_SUCCESS) {
    printf("failed to retreive platform ids: %d\n", err);
    free(pids);
    exit(1);
  }

  /**
   * For each platform, get the devices on it.
   * This algo flattens the list of devices
   * per platform.
   */
  for (cl_uint i = 0; i < p_count; i++) {
    err = clGetDeviceIDs(pids[i], CL_DEVICE_TYPE_GPU, 0, NULL, &d_count);
    if (err != CL_SUCCESS || !d_count)
      continue;

    dids = (cl_device_id *)malloc(sizeof(cl_device_id) * d_count);
    err = clGetDeviceIDs(pids[i], CL_DEVICE_TYPE_GPU, d_count, dids, NULL);
    if (err != CL_SUCCESS) {
      free(dids);
      continue;
    }

    /* Handles devices that do not belong to the first platform. */
    if (total + d_count > device) {
      int index = device - total;

      err = clGetDeviceInfo(dids[index], CL_DEVICE_NAME,
        sizeof(info->name), info->name, NULL);

      if (err != CL_SUCCESS) {
        printf("failed to access device name: %d\n", err);
        free(pids);
        free(dids);
        exit(1);
      }

      err = clGetDeviceInfo(dids[index], CL_DEVICE_GLOBAL_MEM_SIZE,
        sizeof(uint64_t), &info->memory, NULL);

      if (err != CL_SUCCESS) {
        printf("failed to access device global mem size: %d\n", err);
        free(pids);
        free(dids);
        exit(1);
      }

      /**
       * TODO(tynes): figure out how to query for memory bus size and
       * set at info->bits. I can't seem to find a good api for it,
       * just set to 0 for now.
       */
      info->bits = 0;

      err = clGetDeviceInfo(dids[index], CL_DEVICE_MAX_CLOCK_FREQUENCY,
        sizeof(uint32_t), &info->clock_rate, NULL);

      if (err != CL_SUCCESS) {
        printf("failed to access device max clock freq: %d\n", err);
        free(pids);
        free(dids);
        exit(1);
      }

      return true;
    }

    total += d_count;
  }

  free(pids);
  free(dids);
  return false;
}

#endif /* HS_HAS_OPENCL */
