#pragma once

#include "cBackend.h"

void idris2_missing_ffi();

/* Disabled: unique reuse codegen has a double-free bug — the cleanup loop
   frees old args THEN reassigns them, causing use-after-free when the same
   values are reused in the new constructor (e.g. reverseOnto, mapAppend). */
#define idris2_isUnique(x) (0)
void idris2_removeReuseConstructor(Value_Constructor *constr);

Value *idris2_apply_closure(Value *, Value *arg);
Value *idris2_tailcall_apply_closure(Value *_clos, Value *arg);
Value *idris2_trampoline(Value *closure);

int idris2_extractInt(Value *);
