# Progressive Idris — Implementation State

## Test Results: 75/75 passing

### Block 1: Type Synthesis (16/16)

| Test      | Status | Description                        | Notes                                      |
|-----------|--------|------------------------------------|---------------------------------------------|
| add001    | PASS   | `add x y = x + y`                 | Simple alias, no patterns                   |
| add002    | PASS   | `double x = x + x`                | Single-arg alias                            |
| add003    | PASS   | `const x y = x`                   | Multi-arg, unused second arg                |
| add004    | PASS   | `id x = x`                        | Identity function                           |
| add005    | PASS   | `isZero 0 = True; isZero _ = ...` | Multi-clause with Nat constructor           |
| pat001    | PASS   | `myNot True = False; ...`          | Bool pattern matching                       |
| pat002    | PASS   | `myAnd True True = True; ...`      | Two-arg Bool patterns                       |
| pat003    | PASS   | `fromMaybe def Nothing = def; ...` | constSolvable flag solves return type hole  |
| pat004    | PASS   | `myFst (x, _) = x`                | Fixed via constSolvable orientation         |
| pat005    | PASS   | `myLength [] = 0; ...`             | Integer defaulting for numeric literals     |
| case001   | PASS   | `test x = case not x of ...`      | Case expression with Prelude-typed scrutinee|
| let001    | PASS   | `addDouble x y = let s = ...`     | Let binding                                 |
| where001  | PASS   | `sumSq a b = ... where sq x = ...`| Where clause                                |
| multi001  | PASS   | `greet "world" = ...; greet n = .`| String literal patterns                     |
| rec001    | PASS   | `factorial 0 = 1; ...`             | Recursive with numeric patterns             |
| rec002    | PASS   | `fib 0 = 0; fib 1 = 1; ...`       | Multi-clause recursion (fibonacci)          |

### Block 2: Show Inferred Types + Type Generalization (5/5)

| Test      | Status | Description                        | Notes                                      |
|-----------|--------|------------------------------------|---------------------------------------------|
| infer001  | PASS   | `--show-inferred-types` flag       | Displays types for unannotated definitions  |
| gen001    | PASS   | `id' x = x` with Int and String   | Single type param, polymorphic usage        |
| gen002    | PASS   | `const' x y = x` with mixed types | Two type params generalized                 |
| gen003    | PASS   | `myLength` with different element  | Recursive function, list element generalized|
| gen004    | PASS   | `add x y = x + y` (Num a => a)    | Typeclass constraint generalized            |
| gen005    | PASS   | `clamp lo hi x` with nested if     | Ord constraint, case block propagation      |

### Block 3: Annotation Monotonicity (30/30)

| Group    | Pattern                            | v0 | v1 | v2 | Notes                    |
|----------|------------------------------------|----|----|-----|--------------------------|
| mono001  | `add x y = x + y`                 | 7  | 7  | 7   | Num constraint           |
| mono002  | `flipBool True/False`              | F  | F  | F   | Bool patterns            |
| mono003  | `myLength []/_::xs`                | 3  | 3  | 3   | List recursive           |
| mono004  | `fib 0/1/n`                        | 55 | 55 | 55  | Numeric literal patterns |
| mono005  | `id' x = x`                       | ✓  | ✓  | ✓   | Polymorphic identity     |
| mono006  | `sumSq` with `where sq`            | 25 | 25 | 25  | Where clause             |
| mono007  | `case not x of`                    | yes| yes| yes | Case expression          |
| mono008  | `fromMaybe'` Nothing/Just          | ✓  | ✓  | ✓   | Maybe patterns           |
| mono009  | `const' x y = x`                  | ✓  | ✓  | ✓   | Polymorphic, multi-type  |
| mono010  | `(x+y)*(x-y)`                     | 16 | 16 | 16  | Multiple Num ops         |

All 30 tests produce identical output across v0 (unannotated), v1 (partially
annotated), and v2 (fully annotated).

### Block 3: Propagation (5/5)

| Test     | Status | Description                        |
|----------|--------|------------------------------------|
| prop001  | PASS   | Unannotated calls typed function   |
| prop002  | PASS   | Unannotated uses string concat     |
| prop003  | PASS   | Chain through typed root           |
| prop004  | PASS   | Maybe constructor patterns         |
| prop005  | PASS   | Typed where-clause helper          |

### Block 3: Error on Annotation Conflict (5/5)

| Test     | Status | Expected Error                     |
|----------|--------|------------------------------------|
| err001   | PASS   | `Num String` (String + arithmetic) |
| err002   | PASS   | `Num String` (String return + lit) |
| err003   | PASS   | `Integer/String` mismatch (++)     |
| err004   | PASS   | `Bool/Integer` mismatch (patterns) |
| err005   | PASS   | `Integer/String` at call site      |

### Block 5: Level-Adapted Error Messages (2/2)

| Test       | Status | Description                        |
|------------|--------|------------------------------------|
| errmsg001  | PASS   | CantSolveGoal beginner message     |
| errmsg002  | PASS   | UndefinedName beginner message     |

Beginner-friendly messages activate only for Level 0-1 files (no polymorphic
annotations) that have SynthesisedType definitions with PMDef bodies. Adapted
errors: CantConvert, CantSolveGoal, UndefinedName, UnsolvedHoles, InvalidArgs,
MaybeMisspelling.

### Block 4 (v2): Stress Tests (6/6)

| Test        | Status | Description                             | Compile Time |
|-------------|--------|-----------------------------------------|--------------|
| stress001   | PASS   | 20 unannotated functions                | ~3.5s        |
| stress002   | PASS   | 20 mixed-annotation functions           | ~2.8s        |
| stress003   | PASS   | 10-level nested let bindings            | ~1.7s        |
| stress004   | PASS   | 20 unannotated (monotonicity v0)        | ~3s          |
| stress004v1 | PASS   | 20 half-annotated (monotonicity v1)     | ~3s          |
| stress004v2 | PASS   | 20 fully-annotated (monotonicity v2)    | ~3s          |

All 4 typed hole tests:

### Block 4 (v1): Typed Holes (4/4)

| Test     | Status | Description                        |
|----------|--------|------------------------------------|
| hole001  | PASS   | Typed hole in unannotated function |
| hole002  | PASS   | Hole preserves inferred context    |
| hole003  | PASS   | Hole in where clause               |
| hole004  | PASS   | Hole in let binding                |

### Tutorial (4 stages, identical output)

| Stage  | Annotations              | Output Identical |
|--------|--------------------------|------------------|
| Stage0 | Zero                     | ✓                |
| Stage1 | API boundary             | ✓                |
| Stage2 | Full with polymorphism   | ✓                |
| Stage3 | Dependent types+totality | ✓                |

## Architecture

### Typeclass Constraint Inference (3-phase)

**Phase 1** (during elaboration): `synthElabMode` flag in UState suppresses
all `BySearch` constraints during `Defaults` and `LastChance` solving modes.
This prevents typeclass constraints (like `Num ?a`) from eagerly resolving
type metas to `Integer`.

**Phase 2** (after elaboration, before pattern compilation): Turn off
`synthElabMode`, compute the function's unsolved type metas, protect them
with `noSolve`, then retry full constraint solving (`Normal → Defaults →
LastChance`). This lets non-type-meta constraints (like case block
constraints) resolve normally while keeping type metas unsolved for
generalization.

**Literal pattern exception**: `clausesHaveLiteralPats` detects numeric/string
patterns in LHS. When present, type metas are NOT protected — they must
resolve to concrete types for pattern matching.

**Zero-argument guard**: Constants like `bar = 3` don't get `SynthesisedType`
since there's nothing to generalize.

### replaceMetasW (case tree meta replacement)

After `weakenNs`, new binders sit at low indices (0..k-1), not high. The
formula for weakened terms is `pos + depth` (where `pos` is the meta's
position among new binders and `depth` is the number of existing Bind nodes
above). This differs from `replaceMetas` which uses `(depth + k - 1) - pos`
for type terms where new binders are prepended as outer Pi binders.

### Case Block Constraint Propagation

When `if-then-else` (or case expressions) desugar to separate case block
functions, their constraint metas are global BySearch holes — not local
environment bindings. `generaliseType` now:

1. Collects all case block functions transitively reachable from the parent
2. Generalizes each with the same implicit type/constraint Pi binders
3. Updates all call sites (parent + case blocks) to pass the new implicit args
4. Deduplicates constraints with identical types (e.g., `Ord ?a` from `<` and `>`)

Key helpers: `collectCaseBlocks`, `addCBCallArgs`/`addCBCallArgsTree`,
`addImplsToPatCB`, `updatePatCBCalls`, `mkConstraintLocals`,
`deduplicateConstraints`.

### Files Modified

- `src/Core/Context/Context.idr` — `HoleFlags.constSolvable`, `SynthesisedType` DefFlag
- `src/Core/Context/TTC.idr` — TTC tag 14 for `SynthesisedType`
- `src/Core/Unify.idr` — `tryConstantSolve`, Phase 1 suppression in `retryGuess`
- `src/Core/UnifyState.idr` — `synthElabMode`, `synthTypeMetas`, `containsMetaFrom`, `hasMeta`
- `src/TTImp/ProcessDef.idr` — `synthTypeFromPatterns`, `generaliseType`, Phase 2 logic, `clausesHaveLiteralPats`, `replaceMetasW`
- `src/Idris/CommandLine.idr` — `--show-inferred-types` flag
- `src/Idris/Session.idr` / `Options.idr` — `showInferredTypes` session option
- `src/Idris/ProcessIdr.idr` — `showSynthesisedTypes`
- `src/Idris/Progressive/ErrorLevel.idr` — annotation level detection, progressive mode detection
- `src/Idris/Error.idr` — beginner-friendly error messages for progressive modules

## Known Limitations

### pat004: Pair matching — SOLVED

Fixed via `constSolvable` orientation in `unifyBothApps`.

### Ord constraint inference — SOLVED

Nested `if-then-else` desugars to case block functions that don't capture
global BySearch constraint metas. Fixed by propagating generalization to case
blocks: after generalizing the parent function, all reachable case blocks get
the same implicit type/constraint binders, and call sites are updated.
Duplicate constraints (e.g., two `Ord ?a` from `<` and `>`) are deduplicated.

### Higher-order functions

`apply f x = f x` and `compose f g x = f (g x)` require Hindley-Milner
inference to determine that `f` is a function type. This is fundamentally
different from constructor-driven synthesis.

### Technical debt

`believe_me` is used for `IsVar` proofs in `replaceMetas`/`replaceMetasW` and
for scope casts in `prependImplPis`. These are representationally correct but
not statically verified.

## Full Test Suite

Zero regressions on the Idris 2 test suite (705+ tests). The only failures
are pre-existing: `chez014` and `channels009` (Windows-specific).
