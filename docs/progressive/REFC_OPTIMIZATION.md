# RefC Backend — Optimization Analysis

This document maps the current RefC backend architecture, identifies
optimization opportunities, and recommends an implementation order.

---

## 1. Current Architecture

### Pipeline

```
Full TT (type theory)
    |  [type-checking, elaboration, erasure]
    v
CExp (src/Core/CompileExpr.idr)
    |  types, multiplicities, implicits all erased
    v
Lifted (src/Compiler/LambdaLift.idr)
    |  lambdas hoisted to top-level, CForce/CDelay collapsed
    |  dead free-variable elimination, known-call recognition
    v
ANF (src/Compiler/ANF.idr)
    |  de Bruijn → Int IDs, all args are AVar, let-normal form
    v
C source (src/Compiler/RefC/RefC.idr)
    |  name mangling, ownership tracking, trampoline emission
    v
Object file (src/Compiler/RefC/CC.idr)
    |  cc -c with support/refc/ includes
    v
Executable
    |  linked against libidris2_refc, libgmp, libm
```

### Key Source Files

| File | Role |
|------|------|
| `src/Core/CompileExpr.idr` | CExp/ANF type definitions, ConInfo shape hints |
| `src/Compiler/LambdaLift.idr` | Lambda lifting, dead-var elimination, lazy encoding |
| `src/Compiler/ANF.idr` | CExp→ANF transform, `freeVariables`, `usedConstructors` |
| `src/Compiler/RefC/RefC.idr` | C code generator (1024 lines), ownership tracking |
| `src/Compiler/RefC/CC.idr` | C compiler/linker invocation |
| `support/refc/_datatypes.h` | All C struct definitions |
| `support/refc/memoryManagement.c` | `newValue`, `newReference`, `removeReference` |
| `support/refc/runtime.c` | Trampoline, closure dispatch, constructor reuse |
| `support/refc/stringOps.c` | String operations |
| `support/refc/casts.c` | Type casts, arithmetic |
| `support/refc/prim.c` | IORef, Array, Pointer, threading stubs |

### Code Generator State (RefC.idr)

| Ref | Type | Purpose |
|-----|------|---------|
| `ArgCounter` | `Nat` | Fresh temp variable names |
| `EnvTracker` | `Env` | Owned vars + reuse map at each point |
| `OutfileText` | `DList String` | Accumulated C output |
| `IndentLevel` | `Nat` | Indentation depth |
| `FunctionDefinitions` | `List String` | Forward declarations |
| `HeaderFiles` | `SortedSet String` | `#include` from FFI |
| `ConstDef` | `SortedMap Constant ConstDef` | Static constant values |

---

## 2. Value Representation

### Header (4 bytes)

```c
typedef struct {
    uint16_t refCounter;  // UINT16_MAX = immortal
    uint8_t  tag;         // type discriminant
    uint8_t  reserved;
} Value_header;
```

### Pointer Tagging (Unboxed Small Integers)

If `(uintptr_t)p & 3 != 0`, the pointer is not a heap allocation — it is an
immediate value. The integer is stored as `(value << shift) | 1`:
- 64-bit platforms: `shift = 32` — covers Int8, Int16, Int32, Bits8, Bits16, Bits32, Char
- 32-bit platforms: `shift = 16` — covers Int8, Int16, Bits8, Bits16, Char

### Boxed Heap Types

| Type | Tag | Payload | Notes |
|------|-----|---------|-------|
| `Value_Int32` | `INT32_TAG` | `int32_t` | Boxed only on 32-bit |
| `Value_Int64` | `INT64_TAG` | `int64_t` | Always boxed |
| `Value_Bits32` | `BITS32_TAG` | `uint32_t` | Boxed only on 32-bit |
| `Value_Bits64` | `BITS64_TAG` | `uint64_t` | Always boxed |
| `Value_Integer` | `INTEGER_TAG` | `mpz_t` | GMP bignum |
| `Value_Double` | `DOUBLE_TAG` | `double` | Always boxed |
| `Value_String` | `STRING_TAG` | `char *str` | Two allocations |
| `Value_Constructor` | `CONSTRUCTOR_TAG` | `total, tag, name, args[]` | Flexible array |
| `Value_Closure` | `CLOSURE_TAG` | `f, arity, filled, args[]` | Flexible array |
| `Value_IORef` | `IOREF_TAG` | `Value *v` | Mutable reference |
| `Value_Array` | `ARRAY_TAG` | `capacity, Value **arr` | Two allocations |
| `Value_Pointer` | `POINTER_TAG` | `void *p` | Raw C pointer |
| `Value_GCPointer` | `GC_POINTER_TAG` | `p, onCollectFct` | Pointer + finalizer |
| `Value_Buffer` | `BUFFER_TAG` | `Buffer *buffer` | Two allocations |

### Special Representations

- **NULL as unit/nil**: `Nothing`, `[]`, `Z`, `()` are represented as `NULL` pointers
  (zero allocation). `Just`/`::`/`S` are `!= NULL`.
- **Immortal objects**: `refCounter == UINT16_MAX` — refcount operations are skipped.
  Used for static constants and predefined values.
- **Predefined caches**: `Int64[0..99]`, `Bits64[0..99]`, `Integer[0..99]` (lazy),
  empty string — all immortal, avoids allocation for common small values.

### Allocation Strategy

Every value is individually `malloc`'d — no arena, no pool, no bump allocator.
`idris2_newValue(size)` uses `aligned_alloc`/`posix_memalign`/`malloc` to ensure
low bits are clear for pointer tagging. Returns `refCounter = 1, tag = NO_TAG`.

---

## 3. Reference Counting

### Increment (`idris2_newReference`)

- NULL, unboxed, immortal → no-op
- Otherwise `refCounter++`; saturates to `UINT16_MAX` (becomes immortal)

### Decrement (`idris2_removeReference`)

- NULL, unboxed, immortal → no-op
- `refCounter > 1` → decrement and return
- `refCounter == 1` → **free**: recursively remove children by tag, then `free(elem)`:
  - `INTEGER_TAG`: `mpz_clear` then free
  - `STRING_TAG`: `free(str)` then free
  - `CLOSURE_TAG`: removeReference all `args[0..filled-1]`, then free
  - `CONSTRUCTOR_TAG`: removeReference all `args[0..total-1]`, then free
  - `IOREF_TAG`: removeReference stored value, then free
  - `ARRAY_TAG`: removeReference all elements, `free(arr)`, then free
  - `GC_POINTER_TAG`: call finalizer closure, removeReference inner pointer, then free
  - `BUFFER_TAG`: `free(buffer)`, then free
  - Numerics (`INT32/64`, `BITS32/64`, `DOUBLE`): just free
  - `MUTEX_TAG`, `CONDITION_TAG`: **bug** — `pthread_*_destroy` never called

### Ownership Tracking in Code Generator

The `Env` record in RefC.idr tracks:
- `owned : SortedSet AVar` — variables current scope will consume
- `reuseMap : SortedMap Name String` — constructor vars eligible for reuse

`avarToC` emits:
- Owned variable → `var_N` (consumes ownership, removed from set)
- Borrowed variable → `idris2_newReference(var_N)` (increments refcount)

After each `ALet`, variables unused in the body get immediate `idris2_removeReference`.

### Constructor Reuse

In `AConCase`, when matching a constructor:
```c
if (idris2_isUnique(sc)) {
    constructor_N = (Value_Constructor*)sc;  // steal memory
} else {
    // dup all args, decrement sc
}
// later:
if (!constructor_N) constructor_N = idris2_newConstructor(...);
```
If the scrutinee has `refCounter == 1`, its memory is reused for the new
constructor instead of free+malloc.

### No Cycle Detection

Cyclic data (possible via `IORef`) will leak. Idris2's pure functional
core prevents most cycles, but they are theoretically possible.

---

## 4. Closures and Tail Calls

### Closure Representation

```c
typedef struct {
    Value_header header;
    void *f;           // function pointer
    uint8_t arity;     // total args needed
    uint8_t filled;    // args already supplied
    Value *args[];     // flexible array
} Value_Closure;
```

### Application (`idris2_tailcall_apply_closure`)

1. Allocates new closure of size `filled + 1`
2. If old closure is unique: copy arg pointers directly (no inc)
3. If shared: increment all arg refs
4. Append new argument, free/decrement old closure
5. Return new closure (not yet dispatched)

### Dispatch (`idris2_dispatch_closure`)

When `filled == arity`, casts function pointer to `FUN0..FUN16` or `FUNStar`
and calls with all args spread. Arities 0–16 have dedicated fast paths.

### Trampoline (`idris2_trampoline`)

```c
while (it && !unboxed(it) && it->header.tag == CLOSURE_TAG) {
    if (clos->filled < clos->arity) break;  // partial → stop
    it = idris2_dispatch_closure(clos);
    // free/decrement clos
}
return it;
```

Handles tail calls without growing C stack. Each tail-position call returns
a fully-filled closure; the trampoline dispatches it iteratively.

### Tail Position Tracking in Code Generator

`TailPositionStatus = InTailPosition | NotInTailPosition`

- `AAppName` in tail position → `makeClosure` (returned to trampoline)
- `AAppName` not in tail → `idris2_trampoline(directCall(args...))`
- `AApp` in tail → `idris2_tailcall_apply_closure(f, arg)`
- `AApp` not in tail → `idris2_apply_closure(f, arg)` (= tailcall + trampoline)

---

## 5. What Information Is Lost Before ANF

| Information | Erased at |
|-------------|-----------|
| Types (all) | Before CExp |
| Multiplicities (0, 1, ω) | Before CExp |
| Implicit/auto arguments | Before CExp |
| Proof terms, totality | Before CExp |
| Polymorphism (type params) | Before CExp |
| InlineOk tag | Lambda lifting |
| Lambda abstractions | Lambda lifting (hoisted) |
| CForce/CDelay nodes | Lambda lifting (collapsed to lazy annotations) |
| Variable names | ANF (replaced by Int IDs) |

**Critical for optimization**: Multiplicities are erased before CExp reaches
any backend. Linear (Rig1) variables could skip refcounting; erased (Rig0)
could skip code generation entirely. This information is gone by the time
RefC sees it.

---

## 6. Optimization Opportunities

### 6a. Perceus-Style Reuse Analysis

**Current state**: Constructor reuse already exists in a limited form —
`addReuseConstructor` in RefC.idr checks `idris2_isUnique(sc)` at runtime
and reuses the scrutinee's memory in case branches.

**Opportunity**: Extend to Perceus-style static reuse analysis:
- Track which constructor allocations happen after decrement points
- When a decrement-then-allocate sequence targets the same size, fuse into
  in-place reuse without the runtime uniqueness check
- Requires knowing constructor sizes at compile time (already available:
  `total` field = arg count)

**Where it hooks in**:
- `cStatementsFromANF` in RefC.idr, specifically the `ACon` and `AConCase` handlers
- Runtime: `idris2_reuseConstructor` in runtime.c could be extended with
  a `idris2_reuseOrAlloc(old, newSize)` variant

**Complexity**: Medium. The static analysis is the hard part — RefC.idr's
existing `EnvTracker` already tracks ownership, which is the foundation.

### 6b. QTT Multiplicity Exploitation

**Current state**: Multiplicities are completely erased before CExp.
The ANF IR has no knowledge of whether a variable is linear, erased, or
unrestricted.

**Opportunity**:
- **Linear (Rig1)**: No refcounting needed — the variable is used exactly once,
  so it never needs increment and its decrement is the consumption point.
  Could be stack-allocated (no malloc/free overhead).
- **Erased (Rig0)**: Should generate no code at all. Currently these become
  `CErased`→`ANull`, but constructor fields still reserve a `Value*` slot.

**Where multiplicities are erased**:
- `src/Core/CompileExpr.idr` — the `CExp` type has no multiplicity field
- `src/Core/CompileExpr/Compile.idr` or `CompileExpr.idr` `toCExp` — where
  TT terms are compiled to CExp, multiplicities are dropped

**What would be needed**:
1. Thread multiplicity info through CExp → Lifted → ANF (add a `RigCount`
   field to `CLocal`/`ALocal` or to `CDef`/`ANFDef` argument lists)
2. In RefC.idr, emit `avarToC` without `newReference` for Rig1 variables
3. Skip `removeReference` for Rig1 at consumption (ownership transfer is free)
4. For Rig0, skip the `Value*` slot entirely in constructors/closures

**Complexity**: High. Requires changes across the entire compilation pipeline,
not just the backend. The pipeline currently makes no provision for carrying
multiplicity past CExp.

### 6c. Unboxing

**Current state**: Small integers are already unboxed via pointer tagging
(Int8, Int16, Bits8, Bits16, Char, and on 64-bit also Int32, Bits32).
Int64, Bits64, Double are always heap-allocated.

**Opportunity**:
- **Double**: On 64-bit, `double` is 8 bytes = `sizeof(void*)`. Could be
  NaN-boxed or union-punned into the pointer itself, avoiding allocation.
  Significant for numeric-heavy code.
- **Bool**: Currently a `Value_Constructor` with tag 0 or 1 (or NULL/non-NULL
  via ConInfo). Could be unboxed as a tagged pointer.
- **Enum types**: `ConInfo` already has `ENUM n` for types with ≤n nullary
  constructors. These could be unboxed as small integers rather than
  allocated constructors.

**Where unnecessary box/unbox pairs occur**:
- `AOp` primitive operations extract values, compute, then re-box.
  For example `Add IntType` on two `Value_Int64*` calls `idris2_extractInt`
  on both, adds, then `idris2_mkInt64` allocates a new boxed result.
  If the result is immediately consumed by another `AOp`, the intermediate
  allocation is wasted.
- `cOp` in RefC.idr emits `idris2_mkTYPE(op(extract(a), extract(b)))` —
  the extract-op-box pattern could be fused when the result feeds another
  extract.

**Complexity**: Medium for Double NaN-boxing (mostly runtime changes).
Low for ENUM unboxing (code generator change, ConInfo already available).
High for fusing box/unbox chains (requires peephole optimization in RefC.idr
or an ANF-level optimization pass).

### 6d. Known-Call Optimization

**Current state**: Lambda lifting already converts `CApp (CRef n) args` to
`LAppName n args` (→ `AAppName n args`). RefC.idr generates direct C function
calls for these when arity ≤ 16 and not in tail position.

**Remaining opportunity**:
- In tail position, known calls still allocate a closure for the trampoline.
  For self-recursive tail calls, this could be a `goto` or loop instead.
- `AUnderApp` (partial application of known function) always allocates a
  closure. If the partial application is immediately applied to the remaining
  args (e.g., `let f = foo 1 in f 2 3`), the closure allocation is wasted.

**Where it hooks in**:
- `cStatementsFromANF` for `AAppName` in `InTailPosition` (RefC.idr ~line 479)
- Self-tail-call detection would need to compare the called name against the
  enclosing function name

**Complexity**: Low for self-recursive tail-call loops. Medium for partial
application fusion (requires data-flow analysis at ANF level).

### 6e. Tail Call Optimization

**Current state**: Uses trampolining — tail-position calls return a closure
that the trampoline loop dispatches iteratively. This prevents stack overflow
but has overhead: allocating a closure per tail call, plus the trampoline loop.

**Opportunity**:
- **Self-tail-calls → loops**: Detect when a function calls itself in tail
  position and emit a `while(1) { ... }` loop with variable reassignment
  instead of closure allocation. This is the single most impactful TCO
  improvement.
- **Mutual tail calls**: Could use GCC's `musttail` attribute (Clang 13+,
  GCC 14+) or `-foptimize-sibling-calls` pragma, but portability is limited.

**Where it hooks in**:
- `createCFunctions` in RefC.idr for `MkAFun` — wrap the body in a loop
  when self-tail-call is detected
- `cStatementsFromANF` for `AAppName` in tail position — emit `goto` or
  continue instead of `makeClosure`

**Complexity**: Low-Medium for self-tail-calls. High for general mutual TCO.

### 6f. String Optimization

**Current state**:
- Strings are `Value_String` + separately malloc'd `char*`
- Every string operation (concat, substring, reverse, etc.) allocates a new string
- Byte-level operations only — no UTF-8 awareness

**Known bugs/leaks**:
1. **`tail()` empty-string leak** (`stringOps.c` ~line 5): allocates a
   `Value_String` struct then returns the predefined null string without
   freeing the allocated struct.
2. **`getBufferString`** (`buffer.c` ~line 84): returns raw `malloc`'d
   `char*` without wrapping in `Value_String`. Caller must handle lifetime.
3. **`fastPack`/`fastConcat`** (`stringOps.c`): return raw `char*`, not
   `Value*`. Convention requires immediate wrapping, but exception paths leak.

**Optimization opportunities**:
- **String interning / deduplication** for small strings
- **Rope or concat-list** representation to avoid O(n) copies on append
- **Embedded small strings**: For strings ≤ 16 bytes, store the chars inline
  in the `Value_String` struct (like SSO in C++) — eliminates the second
  malloc and improves cache locality
- **Fix the leaks**: Low-hanging fruit, should be done regardless

**Complexity**: Low for leak fixes. Medium for SSO. High for rope representation.

### 6g. Additional Bugs Found

| Bug | File | Description |
|-----|------|-------------|
| `idris2_cast_Double_to_Char` | `casts.h:103` | Missing `(x)` argument to `idris2_vp_to_Double` |
| `String_to_Int64/Bits64` | `casts.c` | Uses `atoi` (int-width), should use `strtoll`/`strtoull` |
| `prim__conditionBroadcast` | `prim.c:216` | Takes `(condition, mutex)` but should take `(condition, world)` |
| Mutex/condvar leak | `memoryManagement.c` | `pthread_*_destroy` never called on free |
| `refc_fork` | `threads.c` | Prints error and calls `exit(0)` — threading not implemented |

---

## 7. Estimated Complexity

| Optimization | Impact | Complexity | Files Changed |
|--------------|--------|------------|---------------|
| Self-tail-call → loop | High | Low | RefC.idr |
| ENUM unboxing | Medium | Low | RefC.idr, runtime.c |
| String leak fixes | Low | Low | stringOps.c, buffer.c |
| Runtime bug fixes | Low | Low | casts.h, casts.c, prim.c, memoryManagement.c |
| Double NaN-boxing | Medium | Medium | _datatypes.h, memoryManagement.c, casts.c |
| Perceus reuse (static) | High | Medium | RefC.idr, runtime.c |
| Known-call in tail pos | Medium | Medium | RefC.idr |
| Box/unbox fusion | Medium | Medium-High | RefC.idr (or new ANF pass) |
| String SSO | Medium | Medium | _datatypes.h, stringOps.c, memoryManagement.c |
| QTT multiplicity threading | High | High | CompileExpr.idr, LambdaLift.idr, ANF.idr, RefC.idr |
| Rope strings | Medium | High | All string-touching files |

---

## 8. Recommended Implementation Order

**Phase 1 — Bug fixes and low-hanging fruit** (days)
1. Fix `tail()` empty-string leak in `stringOps.c`
2. Fix `idris2_cast_Double_to_Char` missing argument in `casts.h`
3. Fix `String_to_Int64/Bits64` `atoi` → `strtoll`/`strtoull` in `casts.c`
4. Fix mutex/condvar destructor leak in `memoryManagement.c`
5. Fix `prim__conditionBroadcast` parameter in `prim.c`

**Phase 2 — Self-tail-call optimization** (days)
6. Detect self-recursive `AAppName` in tail position in RefC.idr
7. Emit `while(1) { ...; continue; }` instead of closure allocation
8. This eliminates the biggest source of allocation in recursive code

**Phase 3 — Unboxing improvements** (1-2 weeks)
9. ENUM types as tagged pointers (ConInfo already has ENUM n)
10. Double NaN-boxing on 64-bit (eliminates allocation for all float ops)
11. Bool as tagged pointer (special case of ENUM)

**Phase 4 — Perceus-style reuse** (2-4 weeks)
12. Static analysis: match decrement points with subsequent allocations
    of the same constructor arity
13. Extend `EnvTracker` to track size-compatible reuse candidates
14. Emit `idris2_reuseOrAlloc` instead of separate free+alloc

**Phase 5 — QTT multiplicity exploitation** (weeks-months)
15. Thread `RigCount` through CExp → Lifted → ANF
16. Skip refcount operations for Rig1 variables in RefC.idr
17. Skip code generation for Rig0 fields
18. Stack-allocate linear values where lifetime is statically known

---

## Appendix: Key Runtime Functions

| Function | File | Purpose |
|----------|------|---------|
| `idris2_newValue` | memoryManagement.c | Aligned malloc + init header |
| `idris2_newReference` | memoryManagement.c | Increment refcount |
| `idris2_removeReference` | memoryManagement.c | Decrement / recursive free |
| `idris2_newConstructor` | memoryManagement.c | Alloc constructor with flexible args |
| `idris2_mkClosure` | memoryManagement.c | Alloc closure with flexible args |
| `idris2_mkInt64/Bits64` | memoryManagement.c | Alloc with [0,99) cache |
| `idris2_mkString` | memoryManagement.c | Alloc with empty-string cache |
| `idris2_dispatch_closure` | runtime.c | Cast fn ptr + call with spread args |
| `idris2_trampoline` | runtime.c | Tail-call loop |
| `idris2_tailcall_apply_closure` | runtime.c | Apply one arg to closure |
| `idris2_apply_closure` | runtime.c | tailcall_apply + trampoline |
| `idris2_isUnique` | runtime.h | `refCounter == 1` check |
| `idris2_extractInt` | runtime.c | Unbox any integer type to int64_t |
