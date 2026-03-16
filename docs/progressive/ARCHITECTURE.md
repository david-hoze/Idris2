# Progressive Idris — Architecture

## Compilation Pipeline

```
Source Code (.idr)
    |
[1] PARSING -> PDecl (src/Idris/Parser.idr)
    |
[2] DESUGARING -> ImpDecl/TTImp (src/Idris/Desugar.idr)
    |
[3] DECLARATION ROUTING (src/TTImp/ProcessDecls.idr)
    |
[4] TYPE DECLARATION -> type added to context (src/TTImp/ProcessType.idr)
    |
[5] DEFINITION PROCESSING -> body elaborated (src/TTImp/ProcessDef.idr)  <-- MAIN CHANGES HERE
    |
[6] ELABORATION -> Term (src/TTImp/Elab.idr)
    |
[7] UNIFICATION -> solve metavariables (src/Core/Unify.idr)  <-- CHANGES HERE
    |
[8-11] COMPILATION -> CExp -> Lambda Lift -> ANF -> Backend
```

## How Progressive Typing Works

### Entry Point: synthTypeFromPatterns

When no type signature is given, `synthTypeFromPatterns` (in `ProcessDef.idr`)
synthesizes a type from patterns with metavariable arguments and return type.
Multi-clause definitions are desugared into single-clause with `case`.

The `SynthesisedType` DefFlag marks definitions whose types were inferred
(not user-declared). Only set for definitions with arguments — nullary
definitions like `bar = 3` don't get this flag.

### The Existing Alias Mechanism

Idris 2 already has `lookupOrAddAlias` (ProcessDef.idr) that accepts
single-clause definitions where all arguments are simple variable bindings.
It generates a "holey type" `_ -> _ -> ... -> _` and registers it.

Progressive typing extends this to handle multi-clause definitions and
constructor patterns by desugaring to single-clause with `case`, then
using `guessScrType` from `Elab.Case` to infer types from constructors.

### Higher-Order Function Inference (Stage 2)

`hasHOFUsage` detects when pattern variables are used as function heads in
clause bodies. When detected, `lookupOrAddAlias` routes to
`synthTypeFromPatterns` instead of the simple alias mechanism.

`scanAppsIn` walks clause bodies and records (name, explicitArgCount) for
each application of a target variable. `maxArityFor` computes the maximum
arity. `enhanceWithHOFAnalysis` replaces bare-hole arg types with function
types of the detected arity.

**Two-path type generation** based on HOF arg count:

- **Single HOF arg** (e.g., `myMap f [] = []; myMap f (x::xs) = f x :: myMap f xs`):
  Uses `mkFuncTypeBindVars` to create IBindVar-named types (`hof0_0 -> hof0_1`),
  then `prependImplicitPis` adds explicit `{hof0_0 : Type} -> {hof0_1 : Type} ->`
  at the outer scope. `bindVarsToVars` converts IBindVar refs to IVar after
  prepending. This avoids the **Pi-scoped codomain problem**: without outer
  binders, inner type metas depend on Pi-bound domain variables, creating
  unsolvable cross-scope constraints.

- **Multiple HOF args** (e.g., `compose f g x = f (g x)`):
  Uses `mkFuncTypeImplicit` to create Implicit-hole types (`_ -> _`). These
  create flexible metavariables that allow cross-arg unification (g's codomain
  can unify with f's domain). IBindVar would create rigid variables that can't
  unify across different HOF args.

### Mutual Recursion Forward Declarations

When processing a `PMutual` block, `processDecl` in `ProcessIdr.idr` generates
IClaim forward declarations for any functions that lack explicit type signatures.
`mutualForwardDecls` scans all PDef clauses via `extractFnEntries`, computes
arity from `countExplicitArgs`, and emits `IClaim` with holey types
(`_ -> _ -> ... -> _`). After processing the forward declarations,
`markForwardDeclHoles` walks each forward-declared name's type and sets the
`constSolvable` flag on all type metas — this is critical because pattern
matching against literal constructors (like `0`, `True`) creates constraints
that `patternEnv` cannot solve (the pattern is a complex expression, not a
simple variable), but `tryConstantSolve` can.

### constSolvable Flag

The `constSolvable` flag on `HoleFlags` allows type metas to be solved by
constant constructors during unification. `tryConstantSolve` in `Unify.idr`
resolves these holes when unified with concrete constructor types (like
`Bool`, `Nat`, `List a`).

### Where-Clause Type Meta Solving (Stage 2)

Where-clause functions inherit the parent's env as their type meta scope.
After pattern matching, constructor args replace Pi-bound variables in the
meta application, causing `patternEnv` to fail. Three mechanisms handle this:

1. **Forward-meta solve** (`tryForwardMeta`): When `?A[a0..an] =?= ?B[b0..bm]`
   with `m <= n` and the first `m` args matching, solve `?A` as a forwarding
   function: `\x0..\xn => ?B[x0..xm]`. Used when e.g. a 3-scope return type
   meta forwards to a 2-scope accumulator type meta.

2. **Same-meta constant solve** (`trySameMetaConst`): When
   `?M[a0..an] =?= ?M[b0..bn]` with some args differing, create a fresh meta
   with only the matching-position Pi binders and solve `?M` via selective
   forwarding. E.g., if args 0 matches but arg 1 differs, solve
   `?M = \x0 => \x1 => ?fresh[x0]`.

3. **Invertible bypass in `unifyBothApps`**: When both sides of a same-meta
   constraint are constSolvable, skip the `unifyArgs` path even if the meta is
   marked invertible. Otherwise `unifyArgs` tries to match constructor args
   positionally (e.g. `x :: rest` vs `rest`) and fails. The `not xcs` guard
   ensures constSolvable metas fall through to the solving-order logic which
   routes to `tryConstantSolve`/`trySameMetaConst`.

## Typeclass Constraint Inference (3-phase)

**Phase 1** (during elaboration): `synthElabMode` flag in UState suppresses
all `BySearch` constraints during `Defaults` and `LastChance` solving modes.
This prevents typeclass constraints (like `Num ?a`) from eagerly resolving
type metas to `Integer`.

**Phase 2** (after elaboration, before pattern compilation): Turn off
`synthElabMode`, compute the function's unsolved type metas, protect them
with `noSolve`, then retry full constraint solving (`Normal -> Defaults ->
LastChance`). This lets non-type-meta constraints (like case block
constraints) resolve normally while keeping type metas unsolved for
generalization.

**Literal pattern exception**: `clausesHaveLiteralPats` detects numeric/string
patterns in LHS. When present, type metas are NOT protected — they must
resolve to concrete types for pattern matching.

## Type Generalization

`generaliseType` (in `ProcessDef.idr`) runs after elaboration. It replaces
unsolved type metas with implicit Pi binders and typeclass constraint metas
with auto-implicit Pi binders.

### replaceMetas / replaceMetasW

`replaceMetas` handles type terms where new binders are prepended as outer
Pi binders. Formula: `(depth + k - 1) - pos`.

`replaceMetasW` handles case tree terms after `weakenNs`, where new binders
sit at low indices (0..k-1). Formula: `pos + depth`.

### Case Block Constraint Propagation

When `if-then-else` (or case expressions) desugar to separate case block
functions, their constraint metas are global BySearch holes — not local
environment bindings. `generaliseType` propagates to case blocks:

1. `collectCaseBlocks` — transitively finds all reachable case block functions
2. Generalizes each with the same implicit type/constraint Pi binders
3. `addCBCallArgs`/`addCBCallArgsTree` — updates call sites with new implicit args
4. `deduplicateConstraints` — merges duplicate constraint types (e.g., two `Ord ?a`)

Other helpers: `addImplsToPatCB`, `updatePatCBCalls`, `mkConstraintLocals`.

## Level-Adapted Error Messages

`src/Idris/Progressive/ErrorLevel.idr` detects:
- **Annotation level** (0-4) based on Pi binder complexity in type terms
- **Progressive mode** — SynthesisedType + PMDef definitions present in namespace

In Level 0-1 progressive modules, 5 error types show beginner-friendly messages:
CantConvert, CantSolveGoal, UndefinedName, UnsolvedHoles, InvalidArgs.
MaybeMisspelling also adapted. Standard Idris 2 modules are unaffected.

## Progressive REPL

`execDecls` in `src/Idris/REPL.idr` records `nextEntry` before processing
declarations. After processing, it scans new context entries for
`SynthesisedType` and auto-displays their types via `displayType`.

`:addtype name` displays the type signature without module prefix, ready
to paste into source code.

## Files Modified

### Core compiler
- `src/Core/Context/Context.idr` — `HoleFlags.constSolvable`, `SynthesisedType` DefFlag
- `src/Core/Context/TTC.idr` — TTC tag 14 for `SynthesisedType`
- `src/Core/Unify.idr` — `tryConstantSolve`, Phase 1 suppression in `retryGuess`
- `src/Core/UnifyState.idr` — `synthElabMode`, `synthTypeMetas`, `containsMetaFrom`, `hasMeta`
- `src/TTImp/ProcessDef.idr` — `synthTypeFromPatterns`, `generaliseType`, Phase 2 logic, `clausesHaveLiteralPats`, `replaceMetasW`

### User interface
- `src/Idris/CommandLine.idr` — `--show-inferred-types` flag
- `src/Idris/Session.idr` / `Options.idr` — `showInferredTypes` session option
- `src/Idris/ProcessIdr.idr` — `showSynthesisedTypes`, mutual forward declarations
- `src/Idris/Desugar/Mutual.idr` — exports `getFnName`, `countExplicitArgs`, `claimedNames`
- `src/Idris/Progressive/ErrorLevel.idr` — annotation level detection, progressive mode detection
- `src/Idris/Error.idr` — beginner-friendly error messages for progressive modules
- `src/Idris/REPL.idr` — auto-display inferred types, `:addtype` command
- `src/Idris/Syntax.idr` — `AddType` REPLCmd constructor
- `src/Idris/Parser.idr` — `:addtype` parser entry

## Technical Debt

`believe_me` is used for `IsVar` proofs in `replaceMetas`/`replaceMetasW` and
for scope casts in `prependImplPis`. These are representationally correct but
not statically verified.
