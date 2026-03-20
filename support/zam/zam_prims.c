#include "zam_vm.h"
#include <inttypes.h>

// Pop one arg from the VM arg stack
static inline Value *pop_arg(ZVM *vm) {
    return (vm->arg_top > 0) ? vm->arg_stack[--vm->arg_top] : NULL;
}

// -----------------------------------------------------------------------
// Small int (Int8/16/32/64, Bits8/16/32/64) arithmetic
// Extracts values as int64, operates, re-encodes as Int32 small int.
// -----------------------------------------------------------------------

static Value *zam_smallint_binop(ZVM *vm, int op) {
    Value *a = pop_arg(vm);
    Value *b = pop_arg(vm);
    int64_t av = 0, bv = 0;
    // Extract integer value from small int or boxed int
    if (a && ((uintptr_t)a & 3) == 1) av = (int64_t)((intptr_t)a >> idris2_vp_int_shift);
    else if (a && IDRIS2_IS_FIXNUM(a)) av = IDRIS2_FIXNUM_VAL(a);
    if (b && ((uintptr_t)b & 3) == 1) bv = (int64_t)((intptr_t)b >> idris2_vp_int_shift);
    else if (b && IDRIS2_IS_FIXNUM(b)) bv = IDRIS2_FIXNUM_VAL(b);
    Value *result = NULL;
    switch (op) {
        case ZAM_PRIM_ADD: result = idris2_mkInt32((int32_t)(av + bv)); break;
        case ZAM_PRIM_SUB: result = idris2_mkInt32((int32_t)(av - bv)); break;
        case ZAM_PRIM_MUL: result = idris2_mkInt32((int32_t)(av * bv)); break;
        case ZAM_PRIM_DIV: result = bv ? idris2_mkInt32((int32_t)(av / bv)) : idris2_mkInt32(0); break;
        case ZAM_PRIM_MOD: result = bv ? idris2_mkInt32((int32_t)(av % bv)) : idris2_mkInt32(0); break;
        case ZAM_PRIM_SHIFTL: result = idris2_mkInt32((int32_t)(av << bv)); break;
        case ZAM_PRIM_SHIFTR: result = idris2_mkInt32((int32_t)(av >> bv)); break;
        case ZAM_PRIM_BAND: result = idris2_mkInt32((int32_t)(av & bv)); break;
        case ZAM_PRIM_BOR:  result = idris2_mkInt32((int32_t)(av | bv)); break;
        case ZAM_PRIM_BXOR: result = idris2_mkInt32((int32_t)(av ^ bv)); break;
        case ZAM_PRIM_LT:   result = idris2_mkBool(av < bv ? 1 : 0); break;
        case ZAM_PRIM_LTE:  result = idris2_mkBool(av <= bv ? 1 : 0); break;
        case ZAM_PRIM_EQ:   result = idris2_mkBool(av == bv ? 1 : 0); break;
        case ZAM_PRIM_GTE:  result = idris2_mkBool(av >= bv ? 1 : 0); break;
        case ZAM_PRIM_GT:   result = idris2_mkBool(av > bv ? 1 : 0); break;
        case ZAM_PRIM_NEG:
            if (b) zam_arg_push(vm, b);
            idris2_removeReference(a);
            return idris2_mkInt32((int32_t)(-av));
    }
    idris2_removeReference(a);
    idris2_removeReference(b);
    return result;
}

// -----------------------------------------------------------------------
// Integer arithmetic (with fixnum fast paths from RefC)
// -----------------------------------------------------------------------

static Value *zam_integer_binop(ZVM *vm, int op) {
    Value *a = pop_arg(vm);
    Value *b = pop_arg(vm);
    Value *result = NULL;
    switch (op) {
        case ZAM_PRIM_ADD: result = idris2_add_Integer(a, b); break;
        case ZAM_PRIM_SUB: result = idris2_sub_Integer(a, b); break;
        case ZAM_PRIM_MUL: result = idris2_mul_Integer(a, b); break;
        case ZAM_PRIM_DIV: result = idris2_div_Integer(a, b); break;
        case ZAM_PRIM_MOD: result = idris2_mod_Integer(a, b); break;
        case ZAM_PRIM_SHIFTL: result = idris2_shiftl_Integer(a, b); break;
        case ZAM_PRIM_SHIFTR: result = idris2_shiftr_Integer(a, b); break;
        case ZAM_PRIM_BAND: result = idris2_and_Integer(a, b); break;
        case ZAM_PRIM_BOR: result = idris2_or_Integer(a, b); break;
        case ZAM_PRIM_BXOR: result = idris2_xor_Integer(a, b); break;
        case ZAM_PRIM_LT:  result = idris2_lt_Integer(a, b); break;
        case ZAM_PRIM_LTE: result = idris2_lte_Integer(a, b); break;
        case ZAM_PRIM_EQ:  result = idris2_eq_Integer(a, b); break;
        case ZAM_PRIM_GTE: result = idris2_gte_Integer(a, b); break;
        case ZAM_PRIM_GT:  result = idris2_gt_Integer(a, b); break;
        case ZAM_PRIM_NEG: {
            // Neg is unary — b is not used, a is the operand
            // But we already popped both. Put b back and negate a.
            // Actually: for Neg, only one arg is on the stack.
            // We popped a (the real arg) and b (garbage / underflow).
            // Fix: Neg should only pop one arg. We'll handle this below.
            // For now, push b back.
            if (b) zam_arg_push(vm, b);
            result = idris2_negate_Integer(a);
            idris2_removeReference(a);
            return result;
        }
    }
    idris2_removeReference(a);
    idris2_removeReference(b);
    return result;
}

// -----------------------------------------------------------------------
// Double arithmetic
// -----------------------------------------------------------------------

static Value *zam_double_binop(ZVM *vm, int op) {
    Value *a = pop_arg(vm);
    Value *b = pop_arg(vm);
    Value *result = NULL;
    switch (op) {
        case ZAM_PRIM_ADD: result = idris2_add_Double(a, b); break;
        case ZAM_PRIM_SUB: result = idris2_sub_Double(a, b); break;
        case ZAM_PRIM_MUL: result = idris2_mul_Double(a, b); break;
        case ZAM_PRIM_DIV: result = idris2_div_Double(a, b); break;
        case ZAM_PRIM_LT:  result = idris2_lt_Double(a, b); break;
        case ZAM_PRIM_LTE: result = idris2_lte_Double(a, b); break;
        case ZAM_PRIM_EQ:  result = idris2_eq_Double(a, b); break;
        case ZAM_PRIM_GTE: result = idris2_gte_Double(a, b); break;
        case ZAM_PRIM_GT:  result = idris2_gt_Double(a, b); break;
        case ZAM_PRIM_NEG:
            if (b) zam_arg_push(vm, b);
            result = idris2_negate_Double(a);
            idris2_removeReference(a);
            return result;
        default: result = NULL; break;
    }
    idris2_removeReference(a);
    idris2_removeReference(b);
    return result;
}

// -----------------------------------------------------------------------
// String comparisons
// -----------------------------------------------------------------------

static Value *zam_string_binop(ZVM *vm, int op) {
    Value *a = pop_arg(vm);
    Value *b = pop_arg(vm);
    Value *result = NULL;
    switch (op) {
        case ZAM_PRIM_LT:  result = idris2_lt_string(a, b); break;
        case ZAM_PRIM_LTE: result = idris2_lte_string(a, b); break;
        case ZAM_PRIM_EQ:  result = idris2_eq_string(a, b); break;
        case ZAM_PRIM_GTE: result = idris2_gte_string(a, b); break;
        case ZAM_PRIM_GT:  result = idris2_gt_string(a, b); break;
        default: result = NULL; break;
    }
    idris2_removeReference(a);
    idris2_removeReference(b);
    return result;
}

// -----------------------------------------------------------------------
// String operations
// -----------------------------------------------------------------------

static Value *zam_string_op(ZVM *vm, uint16_t prim_id) {
    switch (prim_id) {
        case ZAM_PRIM_STRLENGTH: {
            Value *s = pop_arg(vm);
            // stringLength macro returns Int64, but Idris2 Int is Int32 (small int)
            int len = 0;
            if (s && !idris2_vp_is_unboxed(s) && ((Value*)s)->header.tag == STRING_TAG)
                len = (int)strlen(((Value_String *)s)->str);
            idris2_removeReference(s);
            return idris2_mkInt32(len);
        }
        case ZAM_PRIM_STRHEAD: {
            Value *s = pop_arg(vm);
            Value *r = head(s);
            idris2_removeReference(s);
            return r;
        }
        case ZAM_PRIM_STRTAIL: {
            Value *s = pop_arg(vm);
            Value *r = tail(s);
            idris2_removeReference(s);
            return r;
        }
        case ZAM_PRIM_STRINDEX: {
            Value *s = pop_arg(vm);
            Value *i = pop_arg(vm);
            // strIndex uses idris2_vp_to_Int64 but Int is small-int tagged Int32
            int idx = 0;
            if (i && ((uintptr_t)i & 3) == 1)
                idx = (int)((intptr_t)i >> idris2_vp_int_shift);
            else if (i && !idris2_vp_is_unboxed(i))
                idx = idris2_vp_to_Int32(i);
            char *str = ((Value_String *)s)->str;
            Value *r = (Value *)idris2_mkChar((unsigned char)str[idx]);
            idris2_removeReference(s);
            idris2_removeReference(i);
            return r;
        }
        case ZAM_PRIM_STRCONS: {
            Value *c = pop_arg(vm);
            Value *s = pop_arg(vm);
            Value *r = strCons(c, s);
            idris2_removeReference(c);
            idris2_removeReference(s);
            return r;
        }
        case ZAM_PRIM_STRAPPEND: {
            Value *a = pop_arg(vm);
            Value *b = pop_arg(vm);
            Value *r = strAppend(a, b);
            idris2_removeReference(a);
            idris2_removeReference(b);
            return r;
        }
        case ZAM_PRIM_STRREVERSE: {
            Value *s = pop_arg(vm);
            Value *r = reverse(s);
            idris2_removeReference(s);
            return r;
        }
        case ZAM_PRIM_STRSUBSTR: {
            Value *start_v = pop_arg(vm);
            Value *len_v = pop_arg(vm);
            Value *s = pop_arg(vm);
            // Extract Int values (small-int tagged Int32)
            int offset = 0, slen = 0;
            if (start_v && ((uintptr_t)start_v & 3) == 1)
                offset = (int)((intptr_t)start_v >> idris2_vp_int_shift);
            else if (start_v && !idris2_vp_is_unboxed(start_v))
                offset = idris2_vp_to_Int32(start_v);
            if (len_v && ((uintptr_t)len_v & 3) == 1)
                slen = (int)((intptr_t)len_v >> idris2_vp_int_shift);
            else if (len_v && !idris2_vp_is_unboxed(len_v))
                slen = idris2_vp_to_Int32(len_v);
            char *input = ((Value_String *)s)->str;
            int tail_len = (int)strlen(input) - offset;
            if (tail_len < slen) slen = tail_len;
            if (slen < 0) slen = 0;
            Value_String *retVal = idris2_mkEmptyString(slen + 1);
            memcpy(retVal->str, input + offset, slen);
            idris2_removeReference(start_v);
            idris2_removeReference(len_v);
            idris2_removeReference(s);
            return (Value *)retVal;
        }
    }
    return NULL;
}

// -----------------------------------------------------------------------
// Double math functions
// -----------------------------------------------------------------------

static Value *zam_double_math(ZVM *vm, uint16_t prim_id) {
    Value *a = pop_arg(vm);
    double av = idris2_vp_to_Double(a);
    double result;
    switch (prim_id) {
        case ZAM_PRIM_DOUBLEPOW: {
            Value *b = pop_arg(vm);
            result = pow(av, idris2_vp_to_Double(b));
            idris2_removeReference(b);
            break;
        }
        case ZAM_PRIM_DOUBLEEXP:     result = exp(av); break;
        case ZAM_PRIM_DOUBLELOG:     result = log(av); break;
        case ZAM_PRIM_DOUBLESIN:     result = sin(av); break;
        case ZAM_PRIM_DOUBLECOS:     result = cos(av); break;
        case ZAM_PRIM_DOUBLETAN:     result = tan(av); break;
        case ZAM_PRIM_DOUBLEASIN:    result = asin(av); break;
        case ZAM_PRIM_DOUBLEACOS:    result = acos(av); break;
        case ZAM_PRIM_DOUBLEATAN:    result = atan(av); break;
        case ZAM_PRIM_DOUBLESQRT:    result = sqrt(av); break;
        case ZAM_PRIM_DOUBLEFLOOR:   result = floor(av); break;
        case ZAM_PRIM_DOUBLECEILING: result = ceil(av); break;
        default: result = 0.0; break;
    }
    idris2_removeReference(a);
    return idris2_mkDouble(result);
}

// -----------------------------------------------------------------------
// Cast operations
// -----------------------------------------------------------------------

// Extract int64 from any integer representation (small-int 0b01, fixnum 0b11, or boxed)
static inline int64_t zam_extract_int(Value *v) {
    if (!v) return 0;
    uintptr_t tag = (uintptr_t)v & 3;
    if (tag == 1) return (int64_t)((intptr_t)v >> idris2_vp_int_shift);  // small int
    if (tag == 3) return IDRIS2_FIXNUM_VAL(v);                           // fixnum Integer
    if (tag == 0) {
        switch (((Value*)v)->header.tag) {
            case INT32_TAG: return ((Value_Int32*)v)->i32;
            case INT64_TAG: return ((Value_Int64*)v)->i64;
            case INTEGER_TAG: return idris2_mpz_get_int64(((Value_Integer*)v)->i);
            default: return 0;
        }
    }
    return 0;
}

static Value *zam_cast(ZVM *vm, int from_type, int to_type) {
    Value *v = pop_arg(vm);
    Value *result = NULL;

    // For integer-like source types, extract as int64 and re-encode
    if ((from_type <= ZAM_TYPE_BITS64 || from_type == ZAM_TYPE_CHAR) &&
        to_type == ZAM_TYPE_STRING) {
        // Int/Int8/.../Bits64/Char -> String
        int64_t iv = zam_extract_int(v);
        int l = snprintf(NULL, 0, "%" PRId64, iv);
        Value_String *retVal = idris2_mkEmptyString(l + 1);
        sprintf(retVal->str, "%" PRId64, iv);
        result = (Value *)retVal;
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_STRING) {
        // Integer -> String: need full GMP for large integers
        if (IDRIS2_IS_FIXNUM(v) || ((uintptr_t)v & 3) == 1) {
            int64_t iv = zam_extract_int(v);
            int l = snprintf(NULL, 0, "%" PRId64, iv);
            Value_String *retVal = idris2_mkEmptyString(l + 1);
            sprintf(retVal->str, "%" PRId64, iv);
            result = (Value *)retVal;
        } else {
            result = idris2_cast_Integer_to_string(v);
        }
    } else if (from_type == ZAM_TYPE_STRING && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_cast_string_to_Integer(v);
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_DOUBLE) {
        if (IDRIS2_IS_FIXNUM(v) || ((uintptr_t)v & 3) == 1) {
            result = idris2_mkDouble((double)zam_extract_int(v));
        } else {
            result = idris2_cast_Integer_to_Double(v);
        }
    } else if (from_type == ZAM_TYPE_DOUBLE && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_cast_Double_to_Integer(v);
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_INT) {
        result = idris2_mkInt32((int32_t)zam_extract_int(v));
    } else if ((from_type <= ZAM_TYPE_BITS64) && to_type == ZAM_TYPE_INTEGER) {
        // Int/Int8/.../Bits64 -> Integer
        result = idris2_mkInteger_from_int64(zam_extract_int(v));
    } else if (from_type == ZAM_TYPE_CHAR && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_mkInteger_from_int64(zam_extract_int(v));
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_CHAR) {
        result = idris2_mkChar((unsigned char)zam_extract_int(v));
    } else if (from_type == ZAM_TYPE_STRING && to_type == ZAM_TYPE_DOUBLE) {
        result = idris2_cast_string_to_Double(v);
    } else if (from_type == ZAM_TYPE_DOUBLE && to_type == ZAM_TYPE_STRING) {
        result = idris2_cast_Double_to_string(v);
    } else if (from_type == ZAM_TYPE_CHAR && to_type <= ZAM_TYPE_BITS64) {
        // Char -> Int/IntN/BitsN
        result = idris2_mkInt32((int32_t)zam_extract_int(v));
    } else if ((from_type <= ZAM_TYPE_BITS64) && to_type == ZAM_TYPE_CHAR) {
        result = idris2_mkChar((unsigned char)zam_extract_int(v));
    } else if (from_type == ZAM_TYPE_STRING && to_type <= ZAM_TYPE_BITS64) {
        // String -> Int/IntN/BitsN
        if (v && !idris2_vp_is_unboxed(v) && ((Value*)v)->header.tag == STRING_TAG) {
            result = idris2_mkInt32((int32_t)atoll(((Value_String*)v)->str));
        } else {
            result = idris2_mkInt32(0);
        }
    } else if (from_type == ZAM_TYPE_DOUBLE && to_type <= ZAM_TYPE_BITS64) {
        result = idris2_mkInt32((int32_t)idris2_vp_to_Double(v));
    } else if ((from_type <= ZAM_TYPE_BITS64) && to_type == ZAM_TYPE_DOUBLE) {
        result = idris2_mkDouble((double)zam_extract_int(v));
    } else if (from_type <= ZAM_TYPE_BITS64 && to_type <= ZAM_TYPE_BITS64) {
        // IntN -> IntM, BitsN -> BitsM: just re-encode
        result = idris2_mkInt32((int32_t)zam_extract_int(v));
    } else {
        // Identity cast or unhandled
        result = idris2_newReference(v);
    }
    idris2_removeReference(v);
    return result;
}

// -----------------------------------------------------------------------
// Main dispatch
// -----------------------------------------------------------------------

Value *zam_do_prim(ZVM *vm, uint16_t prim_id) {
    // Typed binary/unary ops (prim_id < 256)
    if (prim_id < 256) {
        int op = prim_id >> 4;
        int ty = prim_id & 0xF;

        switch (ty) {
            case ZAM_TYPE_INTEGER:
                return zam_integer_binop(vm, op);
            case ZAM_TYPE_DOUBLE:
                return zam_double_binop(vm, op);
            case ZAM_TYPE_STRING:
                return zam_string_binop(vm, op);
            default:
                // Int, Int8, Int16, Int32, Int64, Bits8, Bits16, Bits32, Bits64
                return zam_smallint_binop(vm, op);
        }
    }

    // String operations
    if (prim_id >= 256 && prim_id <= 263)
        return zam_string_op(vm, prim_id);

    // Double math
    if (prim_id >= 280 && prim_id <= 291)
        return zam_double_math(vm, prim_id);

    // Cast
    if (prim_id >= 300 && prim_id < 500) {
        int idx = prim_id - 300;
        int from_type = idx / 14;
        int to_type = idx % 14;
        return zam_cast(vm, from_type, to_type);
    }

    // BelieveMe
    if (prim_id == ZAM_PRIM_BELIEVEME) {
        Value *a = pop_arg(vm);  // erased type
        Value *b = pop_arg(vm);  // erased type
        Value *c = pop_arg(vm);  // value
        idris2_removeReference(a);
        idris2_removeReference(b);
        return c;
    }

    // Crash
    if (prim_id == ZAM_PRIM_CRASH) {
        Value *a = pop_arg(vm);  // type
        Value *b = pop_arg(vm);  // message
        if (b && !idris2_vp_is_unboxed(b) &&
            ((Value*)b)->header.tag == STRING_TAG) {
            fprintf(stderr, "CRASH: %s\n", ((Value_String *)b)->str);
        }
        idris2_removeReference(a);
        idris2_removeReference(b);
        return NULL;
    }

    fprintf(stderr, "Unknown prim_id: %u\n", prim_id);
    return NULL;
}
