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

// Proofs
#define HS_EPROOFOK 0
#define HS_EHASHMISMATCH 6
#define HS_ESAMEKEY 7
#define HS_ESAMEPATH 8
#define HS_ENEGDEPTH 9
#define HS_EPATHMISMATCH 10
#define HS_ETOODEEP 11
#define HS_EUNKNOWNERROR 12
#define HS_EMALFORMEDNODE 13
#define HS_EINVALIDNODE 14
#define HS_EEARLYEND 15
#define HS_ENORESULT 16
#define HS_EUNEXPECTEDNODE 17
#define HS_ERECORDMISMATCH 18

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

// Brontide
#define HS_EACTONE 27
#define HS_EACTTWO 28
#define HS_EACTTHREE 29
#define HS_EBADSIZE 30
#define HS_EBADTAG 31

// Max
#define HS_MAXERROR 32

const char *
hsk_strerror(int code);

#endif
