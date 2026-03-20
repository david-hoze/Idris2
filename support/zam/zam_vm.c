#include "zam_vm.h"
#include <errno.h>

// -----------------------------------------------------------------------
// Loader: parse .zamc binary file
// -----------------------------------------------------------------------

ZVM *zam_load(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "zam: cannot open %s: %s\n", filename, strerror(errno));
        return NULL;
    }

    // Read entire file
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *data = malloc(file_size);
    if (fread(data, 1, file_size, f) != (size_t)file_size) {
        fprintf(stderr, "zam: short read on %s\n", filename);
        free(data);
        fclose(f);
        return NULL;
    }
    fclose(f);

    // Parse header (20 bytes)
    uint32_t pos = 0;
    uint32_t magic = zam_read_u32(data, &pos);
    if (magic != ZAM_MAGIC) {
        fprintf(stderr, "zam: bad magic 0x%08x (expected IZBC)\n", magic);
        free(data);
        return NULL;
    }
    uint32_t version = zam_read_u32(data, &pos);
    if (version != ZAM_VERSION) {
        fprintf(stderr, "zam: unsupported version %u\n", version);
        free(data);
        return NULL;
    }
    uint32_t entry_point = zam_read_u32(data, &pos);
    uint32_t num_functions = zam_read_u32(data, &pos);
    zam_read_u32(data, &pos); // string_pool_data_size (unused, we parse directly)

    // Parse string pool
    uint32_t num_strings = zam_read_u32(data, &pos);
    char **string_pool = calloc(num_strings, sizeof(char*));
    for (uint32_t i = 0; i < num_strings; i++) {
        uint32_t slen = zam_read_u32(data, &pos);
        string_pool[i] = malloc(slen + 1);
        memcpy(string_pool[i], data + pos, slen);
        string_pool[i][slen] = '\0';
        uint32_t padded = slen + (4 - (slen % 4)) % 4;
        pos += padded;
    }

    // Parse function table
    uint32_t *func_offsets = calloc(num_functions, sizeof(uint32_t));
    char **func_names = calloc(num_functions, sizeof(char*));
    uint16_t *func_arities = calloc(num_functions, sizeof(uint16_t));
    for (uint32_t i = 0; i < num_functions; i++) {
        uint32_t name_id = zam_read_u32(data, &pos);
        func_offsets[i] = zam_read_u32(data, &pos);
        func_arities[i] = zam_read_u16(data, &pos);
        func_names[i] = (name_id < num_strings) ? string_pool[name_id] : "?";
    }

    // Remaining data is bytecode
    uint32_t code_start = pos;
    uint32_t code_size = file_size - code_start;

    // Allocate VM
    ZVM *vm = calloc(1, sizeof(ZVM));
    vm->accu = NULL;  // VNull equivalent
    vm->env = calloc(16, sizeof(Value*));
    vm->env_size = 0;
    vm->env_cap = 16;
    vm->arg_stack = calloc(64, sizeof(Value*));
    vm->arg_top = 0;
    vm->arg_cap = 64;
    vm->ret_stack = calloc(64, sizeof(ZFrame));
    vm->ret_top = 0;
    vm->ret_cap = 64;
    vm->code = data + code_start;
    vm->pc = entry_point;
    vm->code_size = code_size;
    vm->string_pool = string_pool;
    vm->num_strings = num_strings;
    vm->entry_point = entry_point;
    vm->func_offsets = func_offsets;
    vm->func_names = func_names;
    vm->func_arities = func_arities;
    vm->num_functions = num_functions;

    // Keep data alive (code points into it)
    // We leak the header/string pool/function table portion but that's fine

    return vm;
}

// -----------------------------------------------------------------------
// RETURN helper
// -----------------------------------------------------------------------

// Restore VM env from a frame (copies inline data, transfers heap ownership)
static inline void zam_restore_env_from_frame(ZVM *vm, ZFrame *f) {
    // Free current env entries (but reuse array if possible)
    for (int i = 0; i < vm->env_size; i++) {
        idris2_removeReference(vm->env[i]);
    }
    if (f->env_size == 0) {
        // Nothing to restore
        vm->env_size = 0;
    } else if (f->env) {
        // Heap-allocated: transfer ownership
        free(vm->env);
        vm->env = f->env;
        vm->env_size = f->env_size;
        vm->env_cap = f->env_size;
        f->env = NULL;
    } else {
        // Inline: copy to VM env (ensure capacity)
        if (f->env_size > vm->env_cap) {
            vm->env_cap = f->env_size;
            vm->env = realloc(vm->env, vm->env_cap * sizeof(Value*));
        }
        memcpy(vm->env, f->env_inline, f->env_size * sizeof(Value*));
        vm->env_size = f->env_size;
    }
}

static inline int zam_do_return(ZVM *vm) {
    while (vm->ret_top > 0) {
        ZFrame *f = &vm->ret_stack[--vm->ret_top];
        if (f->type == FRAME_RET) {
            vm->pc = f->pc;
            zam_restore_env_from_frame(vm, f);
            return 1;  // success
        }
        // FRAME_MARK: skip
    }
    return 0;  // empty stack = done
}

// -----------------------------------------------------------------------
// Dispatch loop
// -----------------------------------------------------------------------

#if defined(__GNUC__) || defined(__clang__)
#define ZAM_USE_COMPUTED_GOTO
#endif

#ifdef ZAM_PROFILE
static uint64_t op_counts[64];
static uint64_t total_ops;
static const char *op_names[64] = {
    [0x00] = "ACCESS",    [0x01] = "ASSIGN",    [0x02] = "LET",
    [0x03] = "ENDLET",    [0x04] = "GRAB",      [0x05] = "CLOSURE",
    [0x06] = "APPLY",     [0x07] = "TAILAPPLY",
    [0x08] = "PUSHRETADDR",[0x09] = "RETURN",   [0x0A] = "PUSHMARK",
    [0x0B] = "CALL",      [0x0C] = "TAILCALL",  [0x0D] = "MAKEBLOCK",
    [0x0E] = "MAKEBLOCKNAME",[0x0F] = "GETFIELD",
    [0x10] = "SWITCH",    [0x11] = "SWITCHNAME",[0x12] = "CONSTSWITCH",
    [0x13] = "PRIM",      [0x14] = "EXTPRIM",   [0x15] = "PUSH",
    [0x16] = "POP",       [0x17] = "JUMP",      [0x18] = "STOP",
    [0x19] = "ERROR",     [0x1A] = "NULL",
    [0x1C] = "CONST_INT", [0x1D] = "CONST_BIGINT",
    [0x1E] = "CONST_DOUBLE",[0x1F] = "CONST_STRING",
    [0x20] = "CONST_CHAR",[0x21] = "CONST_WORLD",
    [0x30] = "ACCESS_PUSH",[0x31] = "CONST_INT_LET",
    [0x32] = "ACCESS0",   [0x33] = "ACCESS1",
    [0x34] = "ACCESS0_PUSH",[0x35] = "ACCESS1_PUSH",
};
void zam_print_profile(void) {
    fprintf(stderr, "\n=== ZAM Profile (total ops: %llu) ===\n", (unsigned long long)total_ops);
    for (int i = 0; i < 64; i++) {
        if (op_counts[i] > 0 && op_names[i]) {
            fprintf(stderr, "  %-15s %12llu  (%5.2f%%)\n",
                    op_names[i], (unsigned long long)op_counts[i],
                    100.0 * op_counts[i] / total_ops);
        }
    }
}
#define ZAM_COUNT(op) do { op_counts[op]++; total_ops++; } while(0)
#else
#define ZAM_COUNT(op) ((void)0)
#endif

void zam_run(ZVM *vm) {

#ifdef ZAM_USE_COMPUTED_GOTO

    static void *dispatch[] = {
        [ZOP_ACCESS]        = &&op_access,
        [ZOP_ASSIGN]        = &&op_assign,
        [ZOP_LET]           = &&op_let,
        [ZOP_ENDLET]        = &&op_endlet,
        [ZOP_GRAB]          = &&op_grab,
        [ZOP_CLOSURE]       = &&op_closure,
        [ZOP_APPLY]         = &&op_apply,
        [ZOP_TAILAPPLY]     = &&op_tailapply,
        [ZOP_PUSHRETADDR]   = &&op_pushretaddr,
        [ZOP_RETURN]        = &&op_return,
        [ZOP_PUSHMARK]      = &&op_pushmark,
        [ZOP_CALL]          = &&op_call,
        [ZOP_TAILCALL]      = &&op_tailcall,
        [ZOP_MAKEBLOCK]     = &&op_makeblock,
        [ZOP_MAKEBLOCKNAME] = &&op_makeblockname,
        [ZOP_GETFIELD]      = &&op_getfield,
        [ZOP_SWITCH]        = &&op_switch,
        [ZOP_SWITCHNAME]    = &&op_switchname,
        [ZOP_CONSTSWITCH]   = &&op_constswitch,
        [ZOP_PRIM]          = &&op_prim,
        [ZOP_EXTPRIM]       = &&op_extprim,
        [ZOP_PUSH]          = &&op_push,
        [ZOP_POP]           = &&op_pop,
        [ZOP_JUMP]          = &&op_jump,
        [ZOP_STOP]          = &&op_stop,
        [ZOP_ERROR]         = &&op_error,
        [ZOP_NULL]          = &&op_null,
        [0x1B]              = &&op_stop,  // reserved
        [ZOP_CONST_INT]     = &&op_const_int,
        [ZOP_CONST_BIGINT]  = &&op_const_bigint,
        [ZOP_CONST_DOUBLE]  = &&op_const_double,
        [ZOP_CONST_STRING]  = &&op_const_string,
        [ZOP_CONST_CHAR]    = &&op_const_char,
        [ZOP_CONST_WORLD]   = &&op_const_world,
        // Superinstructions
        [ZOP_ACCESS_PUSH]   = &&op_access_push,
        [ZOP_CONST_INT_LET] = &&op_const_int_let,
        [ZOP_ACCESS0]       = &&op_access0,
        [ZOP_ACCESS1]       = &&op_access1,
        [ZOP_ACCESS0_PUSH]  = &&op_access0_push,
        [ZOP_ACCESS1_PUSH]  = &&op_access1_push,
    };

#ifdef ZAM_PROFILE
    #define NEXT do { uint8_t _op = vm->code[vm->pc++]; ZAM_COUNT(_op); goto *dispatch[_op]; } while(0)
#else
    #define NEXT goto *dispatch[vm->code[vm->pc++]]
#endif

#else
    // Fallback: switch-based dispatch
    #define NEXT continue
    for (;;) {
    uint8_t opcode = vm->code[vm->pc++];
    ZAM_COUNT(opcode);
    switch (opcode) {

#endif

    NEXT;

    op_access: {
        uint16_t slot = zam_read_u16(vm->code, &vm->pc);
        if (slot < (uint16_t)vm->env_size) {
            idris2_removeReference(vm->accu);
            vm->accu = idris2_newReference(vm->env[slot]);
        }
        NEXT;
    }

    op_assign: {
        uint16_t slot = zam_read_u16(vm->code, &vm->pc);
        if (slot < (uint16_t)vm->env_size) {
            idris2_removeReference(vm->env[slot]);
            vm->env[slot] = idris2_newReference(vm->accu);
        }
        NEXT;
    }

    op_let: {
        zam_env_push(vm, idris2_newReference(vm->accu));
        NEXT;
    }

    op_endlet: {
        uint16_t n = zam_read_u16(vm->code, &vm->pc);
        for (int i = 0; i < n && vm->env_size > 0; i++) {
            idris2_removeReference(vm->env[--vm->env_size]);
        }
        NEXT;
    }

    op_grab: {
        if (vm->arg_top > 0) {
            Value *arg = vm->arg_stack[--vm->arg_top];
            zam_env_push(vm, arg);  // transfer ownership
            NEXT;
        }
        // No args available — partial application
        {
            // Create closure capturing current env and PC (pointing back to GRAB)
            uint32_t closure_pc = vm->pc - 1;
            idris2_removeReference(vm->accu);
            vm->accu = zam_make_closure(closure_pc, vm->env, vm->env_size);
            // Look for RetFrame+MarkFrame or MarkFrame+RetFrame pattern
            // and return to the caller
            if (vm->ret_top >= 2) {
                ZFrame *top = &vm->ret_stack[vm->ret_top - 1];
                ZFrame *next = &vm->ret_stack[vm->ret_top - 2];
                if (top->type == FRAME_RET && next->type == FRAME_MARK) {
                    vm->ret_top -= 2;
                    vm->pc = top->pc;
                    zam_restore_env_from_frame(vm, top);
                    NEXT;
                }
                if (top->type == FRAME_MARK && next->type == FRAME_RET) {
                    vm->ret_top -= 2;
                    vm->pc = next->pc;
                    zam_restore_env_from_frame(vm, next);
                    NEXT;
                }
            }
            if (vm->ret_top >= 1 && vm->ret_stack[vm->ret_top - 1].type == FRAME_MARK) {
                vm->ret_top--;  // pop mark
            }
            // Return via normal return mechanism
            if (!zam_do_return(vm)) return;
            NEXT;
        }
    }

    op_closure: {
        uint32_t label = zam_read_u32(vm->code, &vm->pc);
        uint16_t env_sz = zam_read_u16(vm->code, &vm->pc);
        idris2_removeReference(vm->accu);
        // Capture first env_sz slots
        int cap_sz = (env_sz < (uint16_t)vm->env_size) ? env_sz : vm->env_size;
        vm->accu = zam_make_closure(label, vm->env, cap_sz);
        NEXT;
    }

    op_apply: {
        if (!vm->accu || !idris2_vp_is_unboxed(vm->accu)) {
            // Check for ZAM closure
            if (vm->accu && ((Value*)vm->accu)->header.tag == ZAM_CLOSURE_TAG) {
                ZAM_Closure *clo = (ZAM_Closure *)vm->accu;
                // Push return frame
                ZFrame frame;
                frame.type = FRAME_RET;
                frame.pc = vm->pc;
                zam_save_env_to_frame(vm, &frame);
                zam_ret_push(vm, frame);
                // Enter closure
                vm->pc = clo->pc;
                // Replace env with closure's captured env
                zam_free_env(vm->env, vm->env_size);
                vm->env_size = clo->env_size;
                vm->env_cap = clo->env_size > 0 ? clo->env_size : 16;
                vm->env = malloc(vm->env_cap * sizeof(Value*));
                for (int i = 0; i < clo->env_size; i++) {
                    vm->env[i] = idris2_newReference(clo->env[i]);
                }
                idris2_removeReference(vm->accu);
                vm->accu = NULL;
                NEXT;
            }
        }
        fprintf(stderr, "APPLY: not a closure\n");
        return;
    }

    op_tailapply: {
        if (vm->accu && !idris2_vp_is_unboxed(vm->accu) &&
            ((Value*)vm->accu)->header.tag == ZAM_CLOSURE_TAG) {
            ZAM_Closure *clo = (ZAM_Closure *)vm->accu;
            vm->pc = clo->pc;
            zam_free_env(vm->env, vm->env_size);
            vm->env_size = clo->env_size;
            vm->env_cap = clo->env_size > 0 ? clo->env_size : 16;
            vm->env = malloc(vm->env_cap * sizeof(Value*));
            for (int i = 0; i < clo->env_size; i++) {
                vm->env[i] = idris2_newReference(clo->env[i]);
            }
            idris2_removeReference(vm->accu);
            vm->accu = NULL;
            NEXT;
        }
        fprintf(stderr, "TAILAPPLY: not a closure\n");
        return;
    }

    op_pushretaddr: {
        uint32_t label = zam_read_u32(vm->code, &vm->pc);
        ZFrame frame;
        frame.type = FRAME_RET;
        frame.pc = label;
        zam_save_env_to_frame(vm, &frame);
        zam_ret_push(vm, frame);
        NEXT;
    }

    op_return: {
        if (!zam_do_return(vm)) return;  // empty stack = done
        NEXT;
    }

    op_pushmark: {
        ZFrame frame = { .type = FRAME_MARK, .pc = 0, .env = NULL, .env_size = 0 };
        zam_ret_push(vm, frame);
        NEXT;
    }

    op_call: {
        uint32_t label = zam_read_u32(vm->code, &vm->pc);
        uint16_t nargs = zam_read_u16(vm->code, &vm->pc);
        (void)nargs;
        // Save current env and push return frame
        ZFrame frame;
        frame.type = FRAME_RET;
        frame.pc = vm->pc;
        zam_save_env_to_frame(vm, &frame);
        zam_ret_push(vm, frame);
        // Reset env and jump
        vm->env_size = 0;
        vm->pc = label;
        NEXT;
    }

    op_tailcall: {
        uint32_t label = zam_read_u32(vm->code, &vm->pc);
        uint16_t nargs = zam_read_u16(vm->code, &vm->pc);
        (void)nargs;
        // Free current env, reset, jump (no return frame)
        for (int i = 0; i < vm->env_size; i++) {
            idris2_removeReference(vm->env[i]);
        }
        vm->env_size = 0;
        vm->pc = label;
        NEXT;
    }

    op_makeblock: {
        uint16_t tag = zam_read_u16(vm->code, &vm->pc);
        uint16_t arity = zam_read_u16(vm->code, &vm->pc);
        Value_Constructor *con = idris2_newConstructor(arity, tag);
        // Pop arity values from arg stack
        for (int i = 0; i < arity; i++) {
            if (vm->arg_top > 0) {
                con->args[i] = vm->arg_stack[--vm->arg_top];
            } else {
                con->args[i] = NULL;
            }
        }
        idris2_removeReference(vm->accu);
        vm->accu = (Value *)con;
        NEXT;
    }

    op_makeblockname: {
        uint32_t name_id = zam_read_u32(vm->code, &vm->pc);
        uint16_t arity = zam_read_u16(vm->code, &vm->pc);
        const char *name = (name_id < (uint32_t)vm->num_strings) ?
                           vm->string_pool[name_id] : "?";
        Value_Constructor *con = idris2_newConstructor(arity, -1);
        con->name = name;
        for (int i = 0; i < arity; i++) {
            if (vm->arg_top > 0) {
                con->args[i] = vm->arg_stack[--vm->arg_top];
            } else {
                con->args[i] = NULL;
            }
        }
        idris2_removeReference(vm->accu);
        vm->accu = (Value *)con;
        NEXT;
    }

    op_getfield: {
        uint16_t pos = zam_read_u16(vm->code, &vm->pc);
        if (vm->accu && !idris2_vp_is_unboxed(vm->accu)) {
            Value_Constructor *con = (Value_Constructor *)vm->accu;
            if (con->header.tag == CONSTRUCTOR_TAG && pos < con->total) {
                Value *field = idris2_newReference(con->args[pos]);
                idris2_removeReference(vm->accu);
                vm->accu = field;
            }
        }
        NEXT;
    }

    op_switch: {
        uint16_t ncases = zam_read_u16(vm->code, &vm->pc);
        int32_t accu_tag = -1;
        if (vm->accu == NULL) {
            // NULL represents nullary constructors (e.g., Nil, Nothing, Z)
            accu_tag = 0;
        } else if (!idris2_vp_is_unboxed(vm->accu) &&
            ((Value*)vm->accu)->header.tag == CONSTRUCTOR_TAG) {
            accu_tag = ((Value_Constructor *)vm->accu)->tag;
        } else if (((uintptr_t)vm->accu & 3) == 1) {
            // Small int tag (0b01) — Bool is represented as Int8 (0=False, 1=True)
            accu_tag = (int32_t)((uintptr_t)vm->accu >> idris2_vp_int_shift);
        } else if (IDRIS2_IS_FIXNUM(vm->accu)) {
            // Fixnum Integer (0b11) — used as constructor tag sometimes
            accu_tag = (int32_t)IDRIS2_FIXNUM_VAL(vm->accu);
        }
        uint32_t target = 0;
        for (int i = 0; i < ncases; i++) {
            int32_t case_tag = zam_read_i32(vm->code, &vm->pc);
            uint32_t label = zam_read_u32(vm->code, &vm->pc);
            if (case_tag == accu_tag) target = label;
        }
        uint8_t has_def = zam_read_u8(vm->code, &vm->pc);
        uint32_t def_label = 0;
        if (has_def) def_label = zam_read_u32(vm->code, &vm->pc);

        if (target) {
            vm->pc = target;
        } else if (has_def) {
            vm->pc = def_label;
        } else {
            fprintf(stderr, "SWITCH: no match for tag %d\n", accu_tag);
            return;
        }
        NEXT;
    }

    op_switchname: {
        uint16_t ncases = zam_read_u16(vm->code, &vm->pc);
        const char *accu_name = NULL;
        if (vm->accu && !idris2_vp_is_unboxed(vm->accu) &&
            ((Value*)vm->accu)->header.tag == CONSTRUCTOR_TAG) {
            accu_name = ((Value_Constructor *)vm->accu)->name;
        }
        uint32_t target = 0;
        for (int i = 0; i < ncases; i++) {
            uint32_t name_id = zam_read_u32(vm->code, &vm->pc);
            uint32_t label = zam_read_u32(vm->code, &vm->pc);
            const char *case_name = (name_id < (uint32_t)vm->num_strings) ?
                                    vm->string_pool[name_id] : "";
            if (accu_name && strcmp(accu_name, case_name) == 0) target = label;
        }
        uint8_t has_def = zam_read_u8(vm->code, &vm->pc);
        uint32_t def_label = 0;
        if (has_def) def_label = zam_read_u32(vm->code, &vm->pc);

        if (target) vm->pc = target;
        else if (has_def) vm->pc = def_label;
        else { fprintf(stderr, "SWITCHNAME: no match\n"); return; }
        NEXT;
    }

    op_constswitch: {
        uint16_t ncases = zam_read_u16(vm->code, &vm->pc);
        uint32_t target = 0;

        for (int i = 0; i < ncases; i++) {
            uint8_t ctype = zam_read_u8(vm->code, &vm->pc);
            int64_t cval = zam_read_i64(vm->code, &vm->pc);
            uint32_t label = zam_read_u32(vm->code, &vm->pc);

            if (!target) {
                // Match against accu
                if ((ctype == ZAM_CONST_INT || ctype == ZAM_CONST_BIGINT || ctype == ZAM_CONST_BITS) &&
                    vm->accu) {
                    int64_t aval;
                    if (IDRIS2_IS_FIXNUM(vm->accu)) {
                        aval = IDRIS2_FIXNUM_VAL(vm->accu);
                    } else if (((uintptr_t)vm->accu & 3) == 1) {
                        // Small int tag (0b01) — Bool/Int8/Ordering encoded as tagged int
                        aval = (int64_t)((uintptr_t)vm->accu >> idris2_vp_int_shift);
                    } else if (!idris2_vp_is_unboxed(vm->accu) &&
                               ((Value*)vm->accu)->header.tag == INTEGER_TAG) {
                        aval = idris2_mpz_get_int64(((Value_Integer*)vm->accu)->i);
                    } else {
                        continue;
                    }
                    if (aval == cval) target = label;
                } else if (ctype == ZAM_CONST_CHAR && vm->accu) {
                    uint32_t accu_char = idris2_vp_to_Char(vm->accu);
                    if ((int64_t)accu_char == cval) target = label;
                } else if (ctype == ZAM_CONST_STR && vm->accu) {
                    // String comparison via string pool
                    uint32_t str_id = (uint32_t)(cval & 0xFFFFFFFF);
                    if (str_id < (uint32_t)vm->num_strings &&
                        !idris2_vp_is_unboxed(vm->accu) &&
                        ((Value*)vm->accu)->header.tag == STRING_TAG) {
                        if (strcmp(((Value_String*)vm->accu)->str,
                                   vm->string_pool[str_id]) == 0) {
                            target = label;
                        }
                    }
                } else if (ctype == ZAM_CONST_DOUBLE && vm->accu) {
                    double dval;
                    memcpy(&dval, &cval, 8);
                    if (!idris2_vp_is_unboxed(vm->accu) &&
                        ((Value*)vm->accu)->header.tag == DOUBLE_TAG) {
                        if (idris2_vp_to_Double(vm->accu) == dval) target = label;
                    }
                }
            }
        }
        uint8_t has_def = zam_read_u8(vm->code, &vm->pc);
        uint32_t def_label = 0;
        if (has_def) def_label = zam_read_u32(vm->code, &vm->pc);

        if (target) vm->pc = target;
        else if (has_def) vm->pc = def_label;
        else { fprintf(stderr, "CONSTSWITCH: no match\n"); return; }
        NEXT;
    }

    op_prim: {
        uint16_t prim_id = zam_read_u16(vm->code, &vm->pc);
        // Inline fixnum fast path for Integer binary ops
        if (prim_id < 240 && (prim_id & 0xF) == ZAM_TYPE_INTEGER && vm->arg_top >= 2) {
            Value *a = vm->arg_stack[vm->arg_top - 1];
            Value *b = vm->arg_stack[vm->arg_top - 2];
            if (IDRIS2_IS_FIXNUM(a) && IDRIS2_IS_FIXNUM(b)) {
                int64_t av = IDRIS2_FIXNUM_VAL(a);
                int64_t bv = IDRIS2_FIXNUM_VAL(b);
                Value *r = NULL;
                switch (prim_id >> 4) {
                    case ZAM_PRIM_ADD: {
                        int64_t rv;
                        if (!__builtin_add_overflow(av, bv, &rv))
                            r = idris2_mkInteger_from_int64(rv);
                        break;
                    }
                    case ZAM_PRIM_SUB: {
                        int64_t rv;
                        if (!__builtin_sub_overflow(av, bv, &rv))
                            r = idris2_mkInteger_from_int64(rv);
                        break;
                    }
                    case ZAM_PRIM_MUL: {
                        int64_t rv;
                        if (!__builtin_mul_overflow(av, bv, &rv))
                            r = idris2_mkInteger_from_int64(rv);
                        break;
                    }
                    case ZAM_PRIM_DIV:
                        if (bv != 0) r = idris2_mkInteger_from_int64(av / bv);
                        break;
                    case ZAM_PRIM_MOD:
                        if (bv != 0) {
                            int64_t rv = av % bv;
                            if (rv < 0) rv += (bv < 0) ? -bv : bv;
                            r = idris2_mkInteger_from_int64(rv);
                        }
                        break;
                    case ZAM_PRIM_LT:
                        r = idris2_mkBool(av < bv ? 1 : 0); break;
                    case ZAM_PRIM_LTE:
                        r = idris2_mkBool(av <= bv ? 1 : 0); break;
                    case ZAM_PRIM_EQ:
                        r = idris2_mkBool(av == bv ? 1 : 0); break;
                    case ZAM_PRIM_GTE:
                        r = idris2_mkBool(av >= bv ? 1 : 0); break;
                    case ZAM_PRIM_GT:
                        r = idris2_mkBool(av > bv ? 1 : 0); break;
                }
                if (r) {
                    vm->arg_top -= 2;  // no removeRef needed for fixnums
                    idris2_removeReference(vm->accu);
                    vm->accu = r;
                    NEXT;
                }
            }
        }
        // Slow path: full dispatch
        Value *result = zam_do_prim(vm, prim_id);
        idris2_removeReference(vm->accu);
        vm->accu = result;
        NEXT;
    }

    op_extprim: {
        uint32_t name_id = zam_read_u32(vm->code, &vm->pc);
        uint16_t nargs = zam_read_u16(vm->code, &vm->pc);

        const char *name = (name_id < (uint32_t)vm->num_strings) ?
                           vm->string_pool[name_id] : "";

        // Collect args from arg stack
        Value **args = NULL;
        if (nargs > 0) {
            args = alloca(nargs * sizeof(Value*));
            for (int i = 0; i < nargs; i++) {
                args[i] = (vm->arg_top > 0) ? vm->arg_stack[--vm->arg_top] : NULL;
            }
        }

        Value *result = NULL;

        if (strcmp(name, "Prelude.IO.prim__putStr") == 0 ||
            strcmp(name, "prelude.prim__putStr") == 0) {
            if (nargs >= 1 && args[0] && !idris2_vp_is_unboxed(args[0]) &&
                ((Value*)args[0])->header.tag == STRING_TAG) {
                printf("%s", ((Value_String *)args[0])->str);
                fflush(stdout);
            }
            result = NULL;
        } else if (strcmp(name, "Prelude.IO.prim__getStr") == 0 ||
                   strcmp(name, "prelude.prim__getStr") == 0) {
            char line[4096];
            if (fgets(line, sizeof(line), stdin)) {
                size_t len = strlen(line);
                if (len > 0 && line[len-1] == '\n') line[len-1] = '\0';
                result = (Value *)idris2_mkString(line);
            } else {
                result = (Value *)idris2_mkString("");
            }
        } else if (strcmp(name, "Prelude.Types.fastUnpack") == 0 ||
                   strcmp(name, "prelude.fastUnpack") == 0) {
            if (nargs >= 1 && args[0] && !idris2_vp_is_unboxed(args[0]) &&
                ((Value*)args[0])->header.tag == STRING_TAG) {
                result = fastUnpack(((Value_String *)args[0])->str);
            } else {
                result = (Value *)idris2_newConstructor(0, 0);  // Nil
            }
        } else if (strcmp(name, "Prelude.Types.fastPack") == 0 ||
                   strcmp(name, "prelude.fastPack") == 0) {
            if (nargs >= 1) {
                char *s = fastPack(args[0]);
                result = (Value *)idris2_mkString(s);
                free(s);
            } else {
                result = (Value *)idris2_mkString("");
            }
        } else if (strcmp(name, "Prelude.IO.prim__putChar") == 0) {
            if (nargs >= 1 && args[0]) {
                putchar(idris2_vp_to_Char(args[0]));
                fflush(stdout);
            }
            result = NULL;
        } else if (strstr(name, "prim__getArgCount") != NULL) {
            result = idris2_mkInt32(vm->prog_argc);
        } else if (strstr(name, "prim__getArg") != NULL) {
            int idx = (nargs >= 1 && args[0]) ? idris2_vp_to_Int32(args[0]) : 0;
            if (idx >= 0 && idx < vm->prog_argc) {
                result = (Value *)idris2_mkString(vm->prog_argv[idx]);
            } else {
                result = (Value *)idris2_mkString("");
            }
        } else if (strstr(name, "prim__stdin") != NULL) {
            // Return a file pointer — use NULL as a sentinel for stdin
            result = NULL;
        } else if (strstr(name, "fflush") != NULL) {
            fflush(stdout);
            result = NULL;
        } else if (strcmp(name, "Prelude.Types.fastConcat") == 0 ||
                   strcmp(name, "prelude.fastConcat") == 0) {
            if (nargs >= 1) {
                char *s = fastConcat(args[0]);
                result = (Value *)idris2_mkString(s);
                free(s);
            } else {
                result = (Value *)idris2_mkString("");
            }
        }
        else if (strstr(name, "prim__newIORef") != NULL) {
            // prim__newIORef(erased_type, initial_value, world)
            Value *val = (nargs >= 2) ? args[1] : NULL;
            Value_IORef *ioRef = IDRIS2_NEW_VALUE(Value_IORef);
            ioRef->header.tag = IOREF_TAG;
            ioRef->v = idris2_newReference(val);
            result = (Value *)ioRef;
        } else if (strstr(name, "prim__readIORef") != NULL) {
            // prim__readIORef(erased_type, ioref, world)
            Value *ref = (nargs >= 2) ? args[1] : NULL;
            if (ref && !idris2_vp_is_unboxed(ref) &&
                ((Value*)ref)->header.tag == IOREF_TAG) {
                result = idris2_newReference(((Value_IORef *)ref)->v);
            } else {
                result = NULL;
            }
        } else if (strstr(name, "prim__writeIORef") != NULL) {
            // prim__writeIORef(erased_type, ioref, new_value, world)
            Value *ref = (nargs >= 2) ? args[1] : NULL;
            Value *new_val = (nargs >= 3) ? args[2] : NULL;
            if (ref && !idris2_vp_is_unboxed(ref) &&
                ((Value*)ref)->header.tag == IOREF_TAG) {
                Value_IORef *ioref = (Value_IORef *)ref;
                idris2_newReference(new_val);
                Value *old = ioref->v;
                ioref->v = new_val;
                idris2_removeReference(old);
            }
            result = NULL;
        }
        else {
            // Unknown extprim
            fprintf(stderr, "[ZAM] unknown extprim: %s (nargs=%d)\n", name, nargs);
        }
        // For unknown extprims, result stays NULL

        // Free args
        if (args) {
            for (int i = 0; i < nargs; i++) {
                idris2_removeReference(args[i]);
            }
        }

        idris2_removeReference(vm->accu);
        vm->accu = result;
        NEXT;
    }

    op_push: {
        zam_arg_push(vm, idris2_newReference(vm->accu));
        NEXT;
    }

    op_pop: {
        if (vm->arg_top > 0) {
            idris2_removeReference(vm->accu);
            vm->accu = vm->arg_stack[--vm->arg_top];
        }
        NEXT;
    }

    op_jump: {
        uint32_t label = zam_read_u32(vm->code, &vm->pc);
        vm->pc = label;
        NEXT;
    }

    op_stop:
        return;

    op_error: {
        uint32_t str_id = zam_read_u32(vm->code, &vm->pc);
        const char *msg = (str_id < (uint32_t)vm->num_strings) ?
                          vm->string_pool[str_id] : "unknown error";
        fprintf(stderr, "%s\n", msg);
        return;
    }

    op_null: {
        idris2_removeReference(vm->accu);
        vm->accu = NULL;
        NEXT;
    }

    op_const_int: {
        int64_t val = zam_read_i64(vm->code, &vm->pc);
        idris2_removeReference(vm->accu);
        vm->accu = idris2_mkInteger_from_int64(val);
        NEXT;
    }

    op_const_bigint: {
        uint32_t str_id = zam_read_u32(vm->code, &vm->pc);
        const char *s = (str_id < (uint32_t)vm->num_strings) ?
                        vm->string_pool[str_id] : "0";
        idris2_removeReference(vm->accu);
        vm->accu = idris2_mkIntegerLiteral((char*)s);
        NEXT;
    }

    op_const_double: {
        double val = zam_read_f64(vm->code, &vm->pc);
        idris2_removeReference(vm->accu);
        vm->accu = idris2_mkDouble(val);
        NEXT;
    }

    op_const_string: {
        uint32_t str_id = zam_read_u32(vm->code, &vm->pc);
        const char *s = (str_id < (uint32_t)vm->num_strings) ?
                        vm->string_pool[str_id] : "";
        idris2_removeReference(vm->accu);
        vm->accu = (Value *)idris2_mkString((char*)s);
        NEXT;
    }

    op_const_char: {
        uint32_t cp = zam_read_u32(vm->code, &vm->pc);
        idris2_removeReference(vm->accu);
        vm->accu = idris2_mkChar(cp);
        NEXT;
    }

    op_const_world: {
        idris2_removeReference(vm->accu);
        vm->accu = NULL;  // World token = NULL
        NEXT;
    }

    // --- Superinstructions ---

    op_access_push: {
        uint16_t slot = zam_read_u16(vm->code, &vm->pc);
        Value *val = (slot < (uint16_t)vm->env_size) ? vm->env[slot] : NULL;
        idris2_removeReference(vm->accu);
        vm->accu = idris2_newReference(val);
        zam_arg_push(vm, idris2_newReference(val));
        NEXT;
    }

    op_const_int_let: {
        int64_t val = zam_read_i64(vm->code, &vm->pc);
        idris2_removeReference(vm->accu);
        vm->accu = idris2_mkInteger_from_int64(val);
        zam_env_push(vm, idris2_newReference(vm->accu));
        NEXT;
    }

    op_access0: {
        idris2_removeReference(vm->accu);
        vm->accu = (vm->env_size > 0) ? idris2_newReference(vm->env[0]) : NULL;
        NEXT;
    }

    op_access1: {
        idris2_removeReference(vm->accu);
        vm->accu = (vm->env_size > 1) ? idris2_newReference(vm->env[1]) : NULL;
        NEXT;
    }

    op_access0_push: {
        Value *val = (vm->env_size > 0) ? vm->env[0] : NULL;
        idris2_removeReference(vm->accu);
        vm->accu = idris2_newReference(val);
        zam_arg_push(vm, idris2_newReference(val));
        NEXT;
    }

    op_access1_push: {
        Value *val = (vm->env_size > 1) ? vm->env[1] : NULL;
        idris2_removeReference(vm->accu);
        vm->accu = idris2_newReference(val);
        zam_arg_push(vm, idris2_newReference(val));
        NEXT;
    }

#ifndef ZAM_USE_COMPUTED_GOTO
    default:
        fprintf(stderr, "Unknown opcode 0x%02x at pc=%u\n", opcode, vm->pc - 1);
        return;
    } // end switch
    } // end for
#endif
}

// -----------------------------------------------------------------------
// Cleanup
// -----------------------------------------------------------------------

void zam_free(ZVM *vm) {
    if (!vm) return;
    idris2_removeReference(vm->accu);
    zam_free_env(vm->env, vm->env_size);
    // Free arg stack
    for (int i = 0; i < vm->arg_top; i++) {
        idris2_removeReference(vm->arg_stack[i]);
    }
    free(vm->arg_stack);
    // Free ret stack
    for (int i = 0; i < vm->ret_top; i++) {
        if (vm->ret_stack[i].type == FRAME_RET) {
            zam_free_frame_env(&vm->ret_stack[i]);
        }
    }
    free(vm->ret_stack);
    // String pool
    for (int i = 0; i < vm->num_strings; i++) {
        free(vm->string_pool[i]);
    }
    free(vm->string_pool);
    free(vm->func_offsets);
    free(vm->func_names);
    free(vm->func_arities);
    free(vm);
}
