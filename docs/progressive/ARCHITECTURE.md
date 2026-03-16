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

### constSolvable Flag

The `constSolvable` flag on `HoleFlags` allows type metas to be solved by
constant constructors during unification. `tryConstantSolve` in `Unify.idr`
resolves these holes when unified with concrete constructor types (like
`Bool`, `Nat`, `List a`).

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
- `src/Idris/ProcessIdr.idr` — `showSynthesisedTypes`
- `src/Idris/Progressive/ErrorLevel.idr` — annotation level detection, progressive mode detection
- `src/Idris/Error.idr` — beginner-friendly error messages for progressive modules
- `src/Idris/REPL.idr` — auto-display inferred types, `:addtype` command
- `src/Idris/Syntax.idr` — `AddType` REPLCmd constructor
- `src/Idris/Parser.idr` — `:addtype` parser entry

## Technical Debt

`believe_me` is used for `IsVar` proofs in `replaceMetas`/`replaceMetasW` and
for scope casts in `prependImplPis`. These are representationally correct but
not statically verified.
