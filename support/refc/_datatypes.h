#pragma once

#include <gmp.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.h"

#define NO_TAG 0
#define BITS32_TAG 3
#define BITS64_TAG 4
#define INT32_TAG 7
#define INT64_TAG 8
#define INTEGER_TAG 9
#define DOUBLE_TAG 10
#define STRING_TAG 12

#define CLOSURE_TAG 15
#define CONSTRUCTOR_TAG 17

#define IOREF_TAG 20
#define ARRAY_TAG 21
#define POINTER_TAG 22
#define GC_POINTER_TAG 23
#define BUFFER_TAG 24

#define MUTEX_TAG 30
#define CONDITION_TAG 31

typedef struct {
  // Objects that reach the maximum reference count will be immortalized.
  // This 'immortalization' feature is also utilized to prevent statically
  // allocated objects from being destroyed.
#define IDRIS2_VP_REFCOUNTER_MAX UINT16_MAX
  uint16_t refCounter;
  uint8_t tag;
  uint8_t reserved;
} Value_header;
#define IDRIS2_STOCKVAL(t)                                                     \
  { IDRIS2_VP_REFCOUNTER_MAX, t, 0 }

typedef struct {
  Value_header header;
  // `Value` is an "abstract" struct,
  // `Value_Xxx` structs have the same header
  // followed by type-specific payload.
} Value;

/*
We expect at least 4 bytes for `Value_header` alignment, to use bit0 and bit1 of
pointer as flags.

RefC does not have complete static tracking of type information, so types are
identified at runtime using Value_Header's tag field. However, Int that are
pretending to be pointers cannot have that tag, so use that flag to identify
them first. Of course, this flag is not used if it is clear that Value* is
actually an Int. But places like newReference/removeReference require this flag.
 */
#define idris2_vp_is_unboxed(p) ((uintptr_t)(p)&3)

/* Pointer tag dispatch (2-bit):
 *   0b00 = heap pointer (aligned allocation)
 *   0b01 = small int (Int8-32, Bits8-32, Char)
 *   0b10 = unboxed double (Phase 3b)
 *   0b11 = fixnum Integer (62-bit signed, 64-bit platforms only)
 */
#define IDRIS2_PTR_TAG(p)           ((uintptr_t)(p) & 3)
#define IDRIS2_IS_FIXNUM(p)         (IDRIS2_PTR_TAG(p) == 3)

/* Fixnum encode/decode (62-bit signed, arithmetic shift right) */
#define IDRIS2_FIXNUM_VAL(p)        ((int64_t)((intptr_t)(p) >> 2))
#define IDRIS2_MKFIXNUM(v)          ((Value*)(((intptr_t)(v) << 2) | 3))
#define IDRIS2_FIXNUM_MIN           (-(int64_t)((uint64_t)1 << 61))
#define IDRIS2_FIXNUM_MAX           ((int64_t)(((uint64_t)1 << 61) - 1))
#define IDRIS2_FITS_FIXNUM(v)       ((int64_t)(v) >= IDRIS2_FIXNUM_MIN && (int64_t)(v) <= IDRIS2_FIXNUM_MAX)

/* Conservative check: rejects -2^61 (sizeinbase for |(-2^61)| is 62) but that's one value */
#define IDRIS2_MPZ_FITS_FIXNUM(z)   (mpz_sizeinbase(z, 2) <= 61)

/* Set mpz from int64, handling platforms where long < 64 bits (e.g. Windows) */
static inline void idris2_mpz_init_set_int64(mpz_t z, int64_t v) {
#if LONG_MAX >= INT64_MAX
  mpz_init_set_si(z, (long)v);
#else
  mpz_init(z);
  if (v >= 0) {
    mpz_set_ui(z, (unsigned long)(uint32_t)((uint64_t)v >> 32));
    mpz_mul_2exp(z, z, 32);
    mpz_add_ui(z, z, (unsigned long)(uint32_t)v);
  } else {
    uint64_t abs_v = (uint64_t)(-(v + 1)) + 1u;
    mpz_set_ui(z, (unsigned long)(uint32_t)(abs_v >> 32));
    mpz_mul_2exp(z, z, 32);
    mpz_add_ui(z, z, (unsigned long)(uint32_t)abs_v);
    mpz_neg(z, z);
  }
#endif
}

/* Get int64 from mpz. Only call when IDRIS2_MPZ_FITS_FIXNUM is true. */
static inline int64_t idris2_mpz_get_int64(mpz_srcptr z) {
#if LONG_MAX >= INT64_MAX
  return (int64_t)mpz_get_si(z);
#else
  int neg = mpz_sgn(z) < 0;
  uint64_t uv = 0;
  mpz_export(&uv, NULL, -1, sizeof(uint64_t), 0, 0, z);
  return neg ? -(int64_t)uv : (int64_t)uv;
#endif
}

/* idris2_Integer_mpz and idris2_Integer_result defined after Value_Integer struct */

#define idris2_vp_int_shift                                                    \
  ((sizeof(uintptr_t) >= 8 && sizeof(Value *) >= 8) ? 32 : 16)

#define idris2_vp_to_Bits64(p) (((Value_Bits64 *)(p))->ui64)

#if !defined(UINTPTR_WIDTH)
#define idris2_vp_to_Bits32(p)                                                 \
  ((idris2_vp_int_shift == 16)                                                 \
       ? (((Value_Bits32 *)(p))->ui32)                                         \
       : ((uint32_t)((uintptr_t)(p) >> idris2_vp_int_shift)))
#define idris2_vp_to_Int32(p)                                                  \
  ((idris2_vp_int_shift == 16)                                                 \
       ? (((Value_Int32 *)(p))->i32)                                           \
       : ((int32_t)((uintptr_t)(p) >> idris2_vp_int_shift)))

#elif UINTPTR_WIDTH >= 64
// NOTE: We stole two bits from pointer. So, even if we have 64-bit CPU,
//  Int64/Bits654 are not unboxable.
#define idris2_vp_to_Bits32(p)                                                 \
  ((uint32_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Int32(p) ((int32_t)((uintptr_t)(p) >> idris2_vp_int_shift))

#elif UINTPTR_WIDTH >= 32
#define idris2_vp_to_Bits32(p) (((Value_Bits32 *)(p))->ui32)
#define idris2_vp_to_Int32(p) (((Value_Int32 *)(p))->i32)

#else
#error "unsupported uintptr_t width"
#endif

#define idris2_vp_to_Bits16(p)                                                 \
  ((uint16_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Bits8(p) ((uint8_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Int64(p) (((Value_Int64 *)(p))->i64)
#define idris2_vp_to_Int16(p) ((int16_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Int8(p) ((int8_t)((uintptr_t)(p) >> idris2_vp_int_shift))
#define idris2_vp_to_Char(p)                                                   \
  ((unsigned char)((uintptr_t)(p) >> idris2_vp_int_shift))
/* idris2_vp_to_Double defined after Value_Double struct below */
#define idris2_vp_to_Bool(p) (idris2_vp_to_Int8(p))

typedef struct {
  Value_header header;
  uint32_t ui32;
} Value_Bits32;

typedef struct {
  Value_header header;
  uint64_t ui64;
} Value_Bits64;

typedef struct {
  Value_header header;
  int32_t i32;
} Value_Int32;

typedef struct {
  Value_header header;
  int64_t i64;
} Value_Int64;

typedef struct {
  Value_header header;
  mpz_t i;
} Value_Integer;

typedef struct {
  Value_header header;
  double d;
} Value_Double;

static inline double idris2_vp_to_Double(Value *p) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_PTR_TAG(p) == 2) {
    union { uintptr_t u; double d; } conv;
    conv.u = (uintptr_t)p & ~(uintptr_t)3;
    return conv.d;
  }
  return ((Value_Double *)p)->d;
}

/* Finalize a GMP Integer result: if it fits fixnum, free and return fixnum.
   Takes ownership of the Value_Integer. */
static inline Value *idris2_Integer_result(Value_Integer *v) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_MPZ_FITS_FIXNUM(v->i)) {
    int64_t sv = idris2_mpz_get_int64(v->i);
    mpz_clear(v->i);
    free(v);
    return IDRIS2_MKFIXNUM(sv);
  }
  return (Value *)v;
}

/* Get mpz_srcptr from fixnum or boxed Integer.
   If fixnum, tmp is initialized — caller must mpz_clear(tmp) afterward.
   If boxed, tmp is untouched — caller must NOT mpz_clear(tmp). */
static inline mpz_srcptr idris2_Integer_mpz(Value *v, mpz_t tmp) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(v)) {
    idris2_mpz_init_set_int64(tmp, IDRIS2_FIXNUM_VAL(v));
    return tmp;
  }
  return ((Value_Integer *)v)->i;
}

typedef struct {
  Value_header header;
  char *str;
} Value_String;

typedef struct {
  Value_header header;
  int32_t total;
  int32_t tag;
  char const *name;
  Value *args[];
} Value_Constructor;

typedef struct {
  Value_header header;
  // function type depends on arity, see idris2_dispatch_closure
  void *f;
  uint8_t arity;
  uint8_t filled; // length of args.
  Value *args[];
} Value_Closure;

typedef struct {
  Value_header header;
  Value *v;
} Value_IORef;

typedef struct {
  Value_header header;
  void *p;
} Value_Pointer;

typedef struct {
  Value_header header;
  Value_Pointer *p;
  Value_Closure *onCollectFct;
} Value_GCPointer;

typedef struct {
  Value_header header;
  int capacity;
  Value **arr;
} Value_Array;

typedef struct {
  Value_header header;
  Buffer *buffer;
} Value_Buffer;

typedef struct {
  Value_header header;
  pthread_mutex_t *mutex;
} Value_Mutex;

typedef struct {
  Value_header header;
  pthread_cond_t *cond;
} Value_Condition;

void idris2_dumpMemoryStats(void);
