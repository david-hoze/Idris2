#pragma once

#include "cBackend.h"

Value *idris2_newValue(size_t size);
Value *idris2_newReference(Value *source);
void idris2_removeReference(Value *source);

#define IDRIS2_NEW_VALUE(t) ((t *)idris2_newValue(sizeof(t)))

Value_Constructor *idris2_newConstructor(int total, int tag);
Value_Closure *idris2_mkClosure(Value *(*f)(), uint8_t arity, uint8_t filled);

static inline Value *idris2_mkDouble(double d) {
  if (sizeof(uintptr_t) >= 8 && sizeof(double) <= sizeof(uintptr_t)) {
    union { double dd; uintptr_t u; } conv;
    conv.dd = d;
    return (Value*)((conv.u & ~(uintptr_t)3) | 2);
  } else {
    Value_Double *retVal = IDRIS2_NEW_VALUE(Value_Double);
    retVal->header.tag = DOUBLE_TAG;
    retVal->d = d;
    return (Value *)retVal;
  }
}
#define idris2_mkChar(x)                                                       \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkBits8(x)                                                      \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkBits16(x)                                                     \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))

#if !defined(UINTPTR_WIDTH)
#define idris2_mkBits32(x)                                                     \
  ((idris2_vp_int_shift == 16)                                                 \
       ? (idris2_mkBits32_Boxed(x))                                            \
       : ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1)))
#define idris2_mkInt32(x)                                                      \
  ((idris2_vp_int_shift == 16)                                                 \
       ? (idris2_mkInt32_Boxed(x))                                             \
       : ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1)))

#elif UINTPTR_WIDTH >= 64
#define idris2_mkBits32(x)                                                     \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkInt32(x)                                                      \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))

#elif UINTPTR_WIDTH >= 32
#define idris2_mkBits32(x) (idris2_mkBits32_Boxed(x))
#define idris2_mkInt32(x) (idris2_mkInt32_Boxed(x)))

#else
#error "unsupported uintptr_t width"
#endif

#define idris2_mkInt8(x)                                                       \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkInt16(x)                                                      \
  ((Value *)(((uintptr_t)(x) << idris2_vp_int_shift) + 1))
#define idris2_mkBool(x) (idris2_mkInt8(x))

Value *idris2_mkBits32_Boxed(uint32_t i);
Value *idris2_mkBits64(uint64_t i);
Value *idris2_mkInt32_Boxed(int32_t i);
Value *idris2_mkInt64(int64_t i);

Value_Integer *idris2_mkInteger();
Value *idris2_mkIntegerLiteral(char *i);

/* Create an Integer from an int64: returns fixnum on 64-bit if it fits */
static inline Value *idris2_mkInteger_from_int64(int64_t v) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_FITS_FIXNUM(v))
    return IDRIS2_MKFIXNUM(v);
  Value_Integer *retVal = IDRIS2_NEW_VALUE(Value_Integer);
  retVal->header.tag = INTEGER_TAG;
  idris2_mpz_init_set_int64(retVal->i, v);
  return (Value *)retVal;
}
Value_String *idris2_mkEmptyString(size_t l);
Value_String *idris2_mkString(char *);

Value_Pointer *idris2_makePointer(void *);
Value_GCPointer *idris2_makeGCPointer(void *ptr_Raw,
                                      Value_Closure *onCollectFct);
Value_Buffer *idris2_makeBuffer(void *buf);
Value_Array *idris2_makeArray(int length);

extern Value_Int64 const idris2_predefined_Int64[100];
extern Value_Bits64 const idris2_predefined_Bits64[100];
extern Value_Integer idris2_predefined_Integer[100];
Value *idris2_getPredefinedInteger(int n);
extern Value_String const idris2_predefined_nullstring;

// You need uncomment a debugging code in memoryManagement.c to use this.
void idris2_dumpMemoryStats(void);
