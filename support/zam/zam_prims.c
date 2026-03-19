#include "zam_vm.h"

// Pop one arg from the VM arg stack
static inline Value *pop_arg(ZVM *vm) {
    return (vm->arg_top > 0) ? vm->arg_stack[--vm->arg_top] : NULL;
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
            Value *r = stringLength(s);
            idris2_removeReference(s);
            return r;
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
            Value *r = strIndex(s, i);
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
            Value *s = pop_arg(vm);
            Value *start = pop_arg(vm);
            Value *len = pop_arg(vm);
            Value *r = strSubstr(s, start, len);
            idris2_removeReference(s);
            idris2_removeReference(start);
            idris2_removeReference(len);
            return r;
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

static Value *zam_cast(ZVM *vm, int from_type, int to_type) {
    Value *v = pop_arg(vm);
    Value *result = NULL;

    // Common casts
    if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_STRING) {
        result = idris2_cast_Integer_to_string(v);
    } else if (from_type == ZAM_TYPE_STRING && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_cast_string_to_Integer(v);
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_DOUBLE) {
        result = idris2_cast_Integer_to_Double(v);
    } else if (from_type == ZAM_TYPE_DOUBLE && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_cast_Double_to_Integer(v);
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_INT) {
        result = idris2_cast_Integer_to_Int32(v);
    } else if (from_type == ZAM_TYPE_INT && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_cast_Int32_to_Integer(v);
    } else if (from_type == ZAM_TYPE_CHAR && to_type == ZAM_TYPE_INTEGER) {
        result = idris2_cast_Char_to_Integer(v);
    } else if (from_type == ZAM_TYPE_INTEGER && to_type == ZAM_TYPE_CHAR) {
        result = idris2_cast_Integer_to_Char(v);
    } else if (from_type == ZAM_TYPE_INT && to_type == ZAM_TYPE_STRING) {
        result = idris2_cast_Int32_to_string(v);
    } else if (from_type == ZAM_TYPE_STRING && to_type == ZAM_TYPE_DOUBLE) {
        result = idris2_cast_string_to_Double(v);
    } else if (from_type == ZAM_TYPE_DOUBLE && to_type == ZAM_TYPE_STRING) {
        result = idris2_cast_Double_to_string(v);
    } else if (from_type == ZAM_TYPE_CHAR && to_type == ZAM_TYPE_INT) {
        result = idris2_cast_Char_to_Int32(v);
    } else if (from_type == ZAM_TYPE_INT && to_type == ZAM_TYPE_CHAR) {
        result = idris2_cast_Int32_to_Char(v);
    } else {
        // Identity cast
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
                // For other types, fall through to Integer for now
                return zam_integer_binop(vm, op);
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
