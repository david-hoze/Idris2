#include "mathFunctions.h"
#include "memoryManagement.h"
#include "runtime.h"

/* add */
Value *idris2_add_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x), b = IDRIS2_FIXNUM_VAL(y), r;
    if (!__builtin_add_overflow(a, b, &r))
      return idris2_mkInteger_from_int64(r);
  }
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_add(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* sub */
Value *idris2_sub_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x), b = IDRIS2_FIXNUM_VAL(y), r;
    if (!__builtin_sub_overflow(a, b, &r))
      return idris2_mkInteger_from_int64(r);
  }
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_sub(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* negate */
Value *idris2_negate_Integer(Value *x) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x);
    return idris2_mkInteger_from_int64(-a);
  }
  Value_Integer *retVal = idris2_mkInteger();
  mpz_neg(retVal->i, ((Value_Integer *)x)->i);
  return idris2_Integer_result(retVal);
}

/* mul */
Value *idris2_mul_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x), b = IDRIS2_FIXNUM_VAL(y), r;
    if (!__builtin_mul_overflow(a, b, &r))
      return idris2_mkInteger_from_int64(r);
  }
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_mul(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* div */
Value *idris2_div_Int8(Value *x, Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int8_t num = idris2_vp_to_Int8(x);
  int8_t denom = idris2_vp_to_Int8(y);
  int8_t rem = num % denom;
  return idris2_mkInt8(num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}
Value *idris2_div_Int16(Value *x, Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int16_t num = idris2_vp_to_Int16(x);
  int16_t denom = idris2_vp_to_Int16(y);
  int16_t rem = num % denom;
  return idris2_mkInt16(num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}
Value *idris2_div_Int32(Value *x, Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int32_t num = idris2_vp_to_Int32(x);
  int32_t denom = idris2_vp_to_Int32(y);
  int32_t rem = num % denom;
  return idris2_mkInt32(num / denom + ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}
Value *idris2_div_Int64(Value *x, Value *y) {
  // Correction term added to convert from truncated division (C default) to
  // Euclidean division For proof of correctness, see Division and Modulus for
  // Computer Scientists (Daan Leijen)
  // https://www.microsoft.com/en-us/research/publication/division-and-modulus-for-computer-scientists/

  int64_t num = idris2_vp_to_Int64(x);
  int64_t denom = idris2_vp_to_Int64(y);
  int64_t rem = num % denom;
  return (Value *)idris2_mkInt64(num / denom +
                                 ((rem < 0) ? (denom < 0) ? 1 : -1 : 0));
}

Value *idris2_div_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x), b = IDRIS2_FIXNUM_VAL(y);
    int64_t q = a / b;
    int64_t r = a % b;
    if (r < 0) q += (b < 0) ? 1 : -1;
    return idris2_mkInteger_from_int64(q);
  }
  mpz_t tx, ty, rem, yq;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  mpz_inits(rem, yq, NULL);
  mpz_mod(rem, xp, yp);
  mpz_sub(yq, xp, rem);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_divexact(retVal->i, yq, yp);
  mpz_clears(rem, yq, NULL);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* mod */
Value *idris2_mod_Int8(Value *x, Value *y) {
  int8_t num = idris2_vp_to_Int8(x);
  int8_t denom = idris2_vp_to_Int8(y);
  denom = (denom < 0) ? -denom : denom;
  return (Value *)idris2_mkInt8(num % denom + (num < 0 ? denom : 0));
}

Value *idris2_mod_Int16(Value *x, Value *y) {
  int16_t num = idris2_vp_to_Int16(x);
  int16_t denom = idris2_vp_to_Int16(y);
  denom = (denom < 0) ? -denom : denom;
  return (Value *)idris2_mkInt16(num % denom + (num < 0 ? denom : 0));
}
Value *idris2_mod_Int32(Value *x, Value *y) {
  int32_t num = idris2_vp_to_Int32(x);
  int32_t denom = idris2_vp_to_Int32(y);
  denom = (denom < 0) ? -denom : denom;
  return (Value *)idris2_mkInt32(num % denom + (num < 0 ? denom : 0));
}
Value *idris2_mod_Int64(Value *x, Value *y) {
  int64_t num = idris2_vp_to_Int64(x);
  int64_t denom = idris2_vp_to_Int64(y);
  denom = (denom < 0) ? -denom : denom;
  return (Value *)idris2_mkInt64(num % denom + (num < 0 ? denom : 0));
}
Value *idris2_mod_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x), b = IDRIS2_FIXNUM_VAL(y);
    int64_t r = a % b;
    if (r < 0) r += (b < 0) ? -b : b;
    return idris2_mkInteger_from_int64(r);
  }
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_mod(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* shiftl */
Value *idris2_shiftl_Integer(Value *x, Value *y) {
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mp_bitcnt_t cnt = (mp_bitcnt_t)mpz_get_ui(yp);
  mpz_mul_2exp(retVal->i, xp, cnt);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* shiftr */
Value *idris2_shiftr_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y)) {
    int64_t a = IDRIS2_FIXNUM_VAL(x), b = IDRIS2_FIXNUM_VAL(y);
    if (b >= 0 && b < 63)
      return idris2_mkInteger_from_int64(a >> b);
  }
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mp_bitcnt_t cnt = (mp_bitcnt_t)mpz_get_ui(yp);
  mpz_fdiv_q_2exp(retVal->i, xp, cnt);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* and */
Value *idris2_and_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y))
    return idris2_mkInteger_from_int64(IDRIS2_FIXNUM_VAL(x) & IDRIS2_FIXNUM_VAL(y));
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_and(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* or */
Value *idris2_or_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y))
    return idris2_mkInteger_from_int64(IDRIS2_FIXNUM_VAL(x) | IDRIS2_FIXNUM_VAL(y));
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_ior(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}

/* xor */
Value *idris2_xor_Integer(Value *x, Value *y) {
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x) && IDRIS2_IS_FIXNUM(y))
    return idris2_mkInteger_from_int64(IDRIS2_FIXNUM_VAL(x) ^ IDRIS2_FIXNUM_VAL(y));
  mpz_t tx, ty;
  mpz_srcptr xp = idris2_Integer_mpz(x, tx);
  mpz_srcptr yp = idris2_Integer_mpz(y, ty);
  Value_Integer *retVal = idris2_mkInteger();
  mpz_xor(retVal->i, xp, yp);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(x)) mpz_clear(tx);
  if (sizeof(uintptr_t) >= 8 && IDRIS2_IS_FIXNUM(y)) mpz_clear(ty);
  return idris2_Integer_result(retVal);
}
