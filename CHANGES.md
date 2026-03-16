# Progressive Idris — Change Log

## Stage 1: Accept Unannotated Definitions

### Overview
Allow top-level function definitions without type signatures. The compiler
synthesizes metavariable-based types and infers concrete types from usage.

### Key Invariant: Annotation Monotonicity
Adding a type annotation to working code must NEVER change runtime behavior.
It can only:
- Reveal type errors (code was wrong)
- Create typed holes (code doesn't satisfy the stronger spec)

### Changes

#### Block 1: Type Synthesis (16 tests)
- **`synthTypeFromPatterns`** in `ProcessDef.idr`: When no type signature is
  given, synthesize a type from patterns with metavariable arguments and return
  type. Multi-clause definitions are desugared into single-clause with `case`.
- **`SynthesisedType` DefFlag** in `Context.idr`: Marks definitions whose types
  were inferred (not user-declared). Only set for definitions with arguments.
- **`constSolvable` HoleFlag** in `Context.idr`: Allows type metas to be solved
  by constant constructors during unification.
- **`tryConstantSolve`** in `Unify.idr`: Solves constSolvable holes when unified
  with concrete constructor types.
- **`synthElabMode`** in `UnifyState.idr`: Phase 1 — suppresses eager resolution
  of typeclass constraints during synthesis elaboration.
- **`clausesHaveLiteralPats`**: Detects numeric/string patterns that require
  concrete types (not generalizable).
- Modified files: `Context.idr`, `Context/TTC.idr`, `Unify.idr`,
  `UnifyState.idr`, `ProcessDef.idr`

#### Block 2: Show Inferred Types + Generalization (5 tests)
- **`--show-inferred-types`** command-line flag displays synthesized types.
- **`generaliseType`** in `ProcessDef.idr`: After elaboration, replaces unsolved
  type metas with implicit Pi binders and typeclass constraint metas with
  auto-implicit Pi binders. Updates case tree terms via `replaceMetas` and
  `replaceMetasW`.
- **Case block propagation**: `collectCaseBlocks` finds all transitively
  reachable case block functions. Each gets the same implicit binders, and
  call sites are updated with `addCBCallArgs`/`addCBCallArgsTree`.
- **Constraint deduplication**: `deduplicateConstraints` merges identical
  typeclass constraints (e.g., two `Ord ?a` from `<` and `>`).
- Modified files: `ProcessDef.idr`, `CommandLine.idr`, `Session.idr`,
  `Options.idr`, `ProcessIdr.idr`

#### Block 3: Monotonicity + Propagation + Errors (40 tests)
- 10 monotonicity test groups (30 tests): verified that v0 (unannotated),
  v1 (partially annotated), and v2 (fully annotated) produce identical output.
- 5 propagation tests: unannotated functions correctly infer types from
  annotated callees.
- 5 error tests: type conflicts produce clear error messages.

#### Block 4 (v1): Typed Holes (4 tests)
- Typed holes (`?name`) work correctly in unannotated functions, preserving
  inferred type context.

#### Block 5: Level-Adapted Error Messages (2 tests)
- **`ErrorLevel.idr`** (new module): Detects annotation level (0-4) and
  progressive mode (SynthesisedType + PMDef definitions present).
- **Beginner-friendly messages**: In Level 0-1 progressive modules, 5 error
  types show simplified messages: CantConvert, CantSolveGoal, UndefinedName,
  UnsolvedHoles, InvalidArgs. MaybeMisspelling also adapted.
- Only activates when the module actually has progressive definitions — standard
  Idris 2 modules are unaffected.

#### Block 4 (v2): Stress Tests + Documentation (6 tests)
- 4 stress test files (6 test cases): 20 unannotated functions, mixed
  annotations, nested let bindings, monotonicity at scale (3 versions).
- All compile in under 4 seconds.
- `KNOWN_LIMITATIONS.md`: Documents 4 limitations with workarounds.
- `GUIDE.md`: User-facing guide for progressive workflow.

#### Block 6: Progressive REPL (2 features)
- **Auto-display of inferred types**: After `:let` definitions in the REPL,
  unannotated functions automatically show their inferred type.
  ```
  Main> :let add x y = x + y
  add : a -> a -> a
  ```
- **`:addtype` command**: Displays the type signature without module prefix,
  ready to paste into source code.
  ```
  Main> :addtype add
  add : a -> a -> a
  ```
- Modified files: `REPL.idr`, `Syntax.idr`, `Parser.idr`

### Test Results

- **75 progressive tests**: All passing
- **705+ upstream tests**: Zero regressions (only pre-existing `channels009`
  failure on Windows)
