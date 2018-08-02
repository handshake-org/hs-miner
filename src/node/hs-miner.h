#ifndef _HS_MINER_HS_MINER_H
#define _HS_MINER_HS_MINER_H

#include <node.h>
#include <nan.h>

NAN_METHOD(mine);
NAN_METHOD(mine_async);
NAN_METHOD(is_running);
NAN_METHOD(stop);
NAN_METHOD(stop_all);
NAN_METHOD(verify);
NAN_METHOD(blake2b);
NAN_METHOD(sha3);
NAN_METHOD(get_edge_bits);
NAN_METHOD(get_proof_size);
NAN_METHOD(get_perc);
NAN_METHOD(get_easiness);
NAN_METHOD(get_network);
NAN_METHOD(get_backends);
NAN_METHOD(has_cuda);
NAN_METHOD(has_device);
NAN_METHOD(get_device_count);
NAN_METHOD(get_devices);

#endif
