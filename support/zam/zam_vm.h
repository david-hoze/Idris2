#ifndef ZAM_VM_H
#define ZAM_VM_H

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Include RefC runtime for value representation
// Use cBackend.h as the single entry point to avoid circular include issues
#include "../refc/cBackend.h"

// -----------------------------------------------------------------------
// Binary format constants
// -----------------------------------------------------------------------

#define ZAM_MAGIC       0x43425A49  // "IZBC" little-endian
#define ZAM_VERSION     1

// -----------------------------------------------------------------------
// Opcode enumeration — must match Serialize.idr exactly
// -----------------------------------------------------------------------

enum ZamOpcode {
    ZOP_ACCESS        = 0x00,   // uint16 slot
    ZOP_ASSIGN        = 0x01,   // uint16 slot
    ZOP_LET           = 0x02,   // (none)
    ZOP_ENDLET        = 0x03,   // uint16 count
    ZOP_GRAB          = 0x04,   // (none)
    ZOP_CLOSURE       = 0x05,   // uint32 label, uint16 envSize
    ZOP_APPLY         = 0x06,   // (none)
    ZOP_TAILAPPLY     = 0x07,   // (none)
    ZOP_PUSHRETADDR   = 0x08,   // uint32 label
    ZOP_RETURN        = 0x09,   // (none)
    ZOP_PUSHMARK      = 0x0A,   // (none)
    ZOP_CALL          = 0x0B,   // uint32 label, uint16 nargs
    ZOP_TAILCALL      = 0x0C,   // uint32 label, uint16 nargs
    ZOP_MAKEBLOCK     = 0x0D,   // uint16 tag, uint16 arity
    ZOP_MAKEBLOCKNAME = 0x0E,   // uint32 name_id, uint16 arity
    ZOP_GETFIELD      = 0x0F,   // uint16 pos
    ZOP_SWITCH        = 0x10,   // uint16 ncases, (int32 tag, uint32 label)*n, uint8 has_def, [uint32 def]
    ZOP_SWITCHNAME    = 0x11,   // uint16 ncases, (uint32 name_id, uint32 label)*n, uint8 has_def, [uint32]
    ZOP_CONSTSWITCH   = 0x12,   // uint16 ncases, (uint8 type, 8-byte val, uint32 label)*n, uint8 has_def, [uint32]
    ZOP_PRIM          = 0x13,   // uint16 prim_id
    ZOP_EXTPRIM       = 0x14,   // uint32 name_id, uint16 nargs
    ZOP_PUSH          = 0x15,   // (none)
    ZOP_POP           = 0x16,   // (none)
    ZOP_JUMP          = 0x17,   // uint32 label
    ZOP_STOP          = 0x18,   // (none)
    ZOP_ERROR         = 0x19,   // uint32 string_id
    ZOP_NULL          = 0x1A,   // (none)
    // 0x1B reserved
    ZOP_CONST_INT     = 0x1C,   // int64 (8 bytes)
    ZOP_CONST_BIGINT  = 0x1D,   // uint32 string_pool_id
    ZOP_CONST_DOUBLE  = 0x1E,   // double (8 bytes IEEE 754)
    ZOP_CONST_STRING  = 0x1F,   // uint32 string_pool_id
    ZOP_CONST_CHAR    = 0x20,   // uint32 codepoint
    ZOP_CONST_WORLD   = 0x21,   // (none)

    // --- Superinstructions (fused common patterns) ---
    ZOP_ACCESS_PUSH   = 0x30,   // uint16 slot — ACCESS slot; PUSH
    ZOP_CONST_INT_LET = 0x31,   // int64 — CONST_INT v; LET
    ZOP_ACCESS0       = 0x32,   // (none) — ACCESS 0
    ZOP_ACCESS1       = 0x33,   // (none) — ACCESS 1
    ZOP_ACCESS0_PUSH  = 0x34,   // (none) — ACCESS 0; PUSH
    ZOP_ACCESS1_PUSH  = 0x35,   // (none) — ACCESS 1; PUSH
};

// -----------------------------------------------------------------------
// PrimFn encoding — prim_id mapping
//
// Typed binary ops: prim_id = op_kind * 16 + type_idx
//   op_kind: 0=Add,1=Sub,2=Mul,3=Div,4=Mod,5=ShiftL,6=ShiftR,
//            7=BAnd,8=BOr,9=BXOr,10=LT,11=LTE,12=EQ,13=GTE,14=GT
//   type_idx: 0=IntType,1=Int8,2=Int16,3=Int32,4=Int64,5=IntegerType,
//             6=Bits8,7=Bits16,8=Bits32,9=Bits64,10=StringType,
//             11=CharType,12=DoubleType,13=WorldType
//
// Typed unary: 240 + type_idx = Neg
//
// Untyped string ops: 256-263
// Untyped double math: 280-291
// Cast: 300 + from_idx*14 + to_idx
// BelieveMe = 500, Crash = 501
// -----------------------------------------------------------------------

#define ZAM_PRIM_OP(id)    ((id) >> 4)
#define ZAM_PRIM_TYPE(id)  ((id) & 0xF)

#define ZAM_PRIM_ADD    0
#define ZAM_PRIM_SUB    1
#define ZAM_PRIM_MUL    2
#define ZAM_PRIM_DIV    3
#define ZAM_PRIM_MOD    4
#define ZAM_PRIM_SHIFTL 5
#define ZAM_PRIM_SHIFTR 6
#define ZAM_PRIM_BAND   7
#define ZAM_PRIM_BOR    8
#define ZAM_PRIM_BXOR   9
#define ZAM_PRIM_LT     10
#define ZAM_PRIM_LTE    11
#define ZAM_PRIM_EQ     12
#define ZAM_PRIM_GTE    13
#define ZAM_PRIM_GT     14
#define ZAM_PRIM_NEG    15

#define ZAM_TYPE_INT       0
#define ZAM_TYPE_INT8      1
#define ZAM_TYPE_INT16     2
#define ZAM_TYPE_INT32     3
#define ZAM_TYPE_INT64     4
#define ZAM_TYPE_INTEGER   5
#define ZAM_TYPE_BITS8     6
#define ZAM_TYPE_BITS16    7
#define ZAM_TYPE_BITS32    8
#define ZAM_TYPE_BITS64    9
#define ZAM_TYPE_STRING    10
#define ZAM_TYPE_CHAR      11
#define ZAM_TYPE_DOUBLE    12
#define ZAM_TYPE_WORLD     13

#define ZAM_PRIM_STRLENGTH  256
#define ZAM_PRIM_STRHEAD    257
#define ZAM_PRIM_STRTAIL    258
#define ZAM_PRIM_STRINDEX   259
#define ZAM_PRIM_STRCONS    260
#define ZAM_PRIM_STRAPPEND  261
#define ZAM_PRIM_STRREVERSE 262
#define ZAM_PRIM_STRSUBSTR  263

#define ZAM_PRIM_DOUBLEPOW      280
#define ZAM_PRIM_DOUBLEEXP      281
#define ZAM_PRIM_DOUBLELOG      282
#define ZAM_PRIM_DOUBLESIN      283
#define ZAM_PRIM_DOUBLECOS      284
#define ZAM_PRIM_DOUBLETAN      285
#define ZAM_PRIM_DOUBLEASIN     286
#define ZAM_PRIM_DOUBLEACOS     287
#define ZAM_PRIM_DOUBLEATAN     288
#define ZAM_PRIM_DOUBLESQRT     289
#define ZAM_PRIM_DOUBLEFLOOR    290
#define ZAM_PRIM_DOUBLECEILING  291

#define ZAM_PRIM_CAST_BASE  300
// cast prim_id = 300 + from_idx * 14 + to_idx

#define ZAM_PRIM_BELIEVEME  500
#define ZAM_PRIM_CRASH      501

// -----------------------------------------------------------------------
// CONSTSWITCH constant type tags
// -----------------------------------------------------------------------

#define ZAM_CONST_INT     0   // value: int64
#define ZAM_CONST_BIGINT  1   // value: int64 (for matching, or string pool idx)
#define ZAM_CONST_STR     2   // value: uint32 string pool idx (padded to 8)
#define ZAM_CONST_CHAR    3   // value: uint32 codepoint (padded to 8)
#define ZAM_CONST_DOUBLE  4   // value: double (8 bytes)
#define ZAM_CONST_BITS    5   // value: int64 (for Bits8/16/32/64)

// -----------------------------------------------------------------------
// ExtPrim IDs — hardcoded known external primitives
// -----------------------------------------------------------------------

#define ZAM_EXT_PUTSTR       0
#define ZAM_EXT_GETSTR       1
#define ZAM_EXT_PUTCHAR      2
#define ZAM_EXT_GETCHAR      3
#define ZAM_EXT_FASTUNPACK   4
#define ZAM_EXT_FASTPACK     5
#define ZAM_EXT_FASTCONCAT   6
#define ZAM_EXT_NEWIOREF     7
#define ZAM_EXT_READIOREF    8
#define ZAM_EXT_WRITEIOREF   9
#define ZAM_EXT_UNKNOWN      0xFFFF

// -----------------------------------------------------------------------
// Bytecode reader macros
// -----------------------------------------------------------------------

static inline uint8_t  zam_read_u8(const uint8_t *code, uint32_t *pc) {
    return code[(*pc)++];
}
static inline uint16_t zam_read_u16(const uint8_t *code, uint32_t *pc) {
    uint16_t v;
    memcpy(&v, code + *pc, 2);
    *pc += 2;
    return v;
}
static inline uint32_t zam_read_u32(const uint8_t *code, uint32_t *pc) {
    uint32_t v;
    memcpy(&v, code + *pc, 4);
    *pc += 4;
    return v;
}
static inline int32_t zam_read_i32(const uint8_t *code, uint32_t *pc) {
    int32_t v;
    memcpy(&v, code + *pc, 4);
    *pc += 4;
    return v;
}
static inline int64_t zam_read_i64(const uint8_t *code, uint32_t *pc) {
    int64_t v;
    memcpy(&v, code + *pc, 8);
    *pc += 8;
    return v;
}
static inline double zam_read_f64(const uint8_t *code, uint32_t *pc) {
    double v;
    memcpy(&v, code + *pc, 8);
    *pc += 8;
    return v;
}

// -----------------------------------------------------------------------
// VM state
// -----------------------------------------------------------------------

#define ZFRAME_INLINE_ENV 4

typedef struct ZFrame {
    enum { FRAME_RET, FRAME_MARK } type;
    uint32_t pc;            // return address (byte offset)
    Value **env;            // heap-allocated env (NULL if using inline)
    int env_size;
    Value *env_inline[ZFRAME_INLINE_ENV]; // inline storage for small envs
} ZFrame;

#define ZAM_CLOSURE_TAG 40

typedef struct {
    Value_header header;
    uint32_t pc;            // bytecode address
    Value **env;            // captured environment (refcounted)
    int env_size;
} ZAM_Closure;

typedef struct {
    // Registers
    Value *accu;

    // Environment
    Value **env;
    int env_size;
    int env_cap;

    // Argument stack
    Value **arg_stack;
    int arg_top;
    int arg_cap;

    // Return stack
    ZFrame *ret_stack;
    int ret_top;
    int ret_cap;

    // Code
    uint8_t *code;
    uint32_t pc;
    uint32_t code_size;

    // String pool
    char **string_pool;
    int num_strings;

    // Entry point
    uint32_t entry_point;

    // Function table
    uint32_t *func_offsets;
    char **func_names;
    uint16_t *func_arities;
    int num_functions;
} ZVM;

// -----------------------------------------------------------------------
// VM API
// -----------------------------------------------------------------------

ZVM *zam_load(const char *filename);
void zam_run(ZVM *vm);
void zam_free(ZVM *vm);

// Primitive dispatch (implemented in zam_prims.c)
Value *zam_do_prim(ZVM *vm, uint16_t prim_id);

// Environment helpers
static inline void zam_env_push(ZVM *vm, Value *val) {
    if (vm->env_size >= vm->env_cap) {
        vm->env_cap = vm->env_cap ? vm->env_cap * 2 : 16;
        vm->env = realloc(vm->env, vm->env_cap * sizeof(Value*));
    }
    vm->env[vm->env_size++] = val;
}

static inline void zam_arg_push(ZVM *vm, Value *val) {
    if (vm->arg_top >= vm->arg_cap) {
        vm->arg_cap = vm->arg_cap ? vm->arg_cap * 2 : 64;
        vm->arg_stack = realloc(vm->arg_stack, vm->arg_cap * sizeof(Value*));
    }
    vm->arg_stack[vm->arg_top++] = val;
}

static inline void zam_ret_push(ZVM *vm, ZFrame frame) {
    if (vm->ret_top >= vm->ret_cap) {
        vm->ret_cap = vm->ret_cap ? vm->ret_cap * 2 : 64;
        vm->ret_stack = realloc(vm->ret_stack, vm->ret_cap * sizeof(ZFrame));
    }
    vm->ret_stack[vm->ret_top++] = frame;
}

// Save current env into a ZFrame (uses inline storage for small envs)
static inline void zam_save_env_to_frame(ZVM *vm, ZFrame *frame) {
    frame->env_size = vm->env_size;
    if (vm->env_size == 0) {
        frame->env = NULL;
    } else if (vm->env_size <= ZFRAME_INLINE_ENV) {
        frame->env = NULL;  // flag: using inline storage
        for (int i = 0; i < vm->env_size; i++) {
            frame->env_inline[i] = idris2_newReference(vm->env[i]);
        }
    } else {
        frame->env = malloc(vm->env_size * sizeof(Value*));
        for (int i = 0; i < vm->env_size; i++) {
            frame->env[i] = idris2_newReference(vm->env[i]);
        }
    }
}

// Get the env pointer from a frame (inline or heap)
static inline Value **zam_frame_env(ZFrame *f) {
    if (f->env) return f->env;
    return f->env_inline;
}

// Free a frame's saved env
static inline void zam_free_frame_env(ZFrame *f) {
    Value **env = zam_frame_env(f);
    for (int i = 0; i < f->env_size; i++) {
        idris2_removeReference(env[i]);
    }
    if (f->env) free(f->env);  // only free if heap-allocated
}

// Free the VM's current env (always heap-allocated)
static inline void zam_free_env(Value **env, int size) {
    if (!env) return;
    for (int i = 0; i < size; i++) {
        idris2_removeReference(env[i]);
    }
    free(env);
}

// Make a ZAM closure
static inline Value *zam_make_closure(uint32_t pc, Value **env, int env_size) {
    ZAM_Closure *clo = (ZAM_Closure *)idris2_newValue(sizeof(ZAM_Closure));
    clo->header.tag = ZAM_CLOSURE_TAG;
    clo->pc = pc;
    clo->env_size = env_size;
    if (env_size > 0) {
        clo->env = malloc(env_size * sizeof(Value*));
        for (int i = 0; i < env_size; i++) {
            clo->env[i] = idris2_newReference(env[i]);
        }
    } else {
        clo->env = NULL;
    }
    return (Value *)clo;
}

#endif // ZAM_VM_H
