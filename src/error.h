#ifndef _HS_ERRORS_H
#define _HS_ERRORS_H

// Generic
#define HS_SUCCESS 0
#define HS_EOK 0
#define HS_ENOMEM 1
#define HS_ETIMEOUT 2
#define HS_EFAILURE 3
#define HS_EBADARGS 4
#define HS_EENCODING 5

// Device
#define HS_ENODEVICE 6
#define HS_EBADPROPS 7
#define HS_ENOSUPPORT 8
#define HS_EMAXLOAD 9
#define HS_EBADPATH 10
#define HS_ENOSOLUTION 11

// POW
#define HS_ENEGTARGET 19
#define HS_EHIGHHASH 20

// Chain
#define HS_ETIMETOONEW 21
#define HS_EDUPLICATE 22
#define HS_EDUPLICATEORPHAN 23
#define HS_ETIMETOOOLD 24
#define HS_EBADDIFFBITS 25
#define HS_EORPHAN 26

// Cancelled by parrallel CPU thread
#define HS_EABORT 0

// Max
#define HS_MAXERROR 32

const char *
hsk_strerror(int code);

#endif
