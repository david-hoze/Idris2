# Progressive Idris — Implementation State

## Test Results: 9/10 passing

| Test    | Status | Description                        | Notes                                      |
|---------|--------|------------------------------------|---------------------------------------------|
| add001  | PASS   | `add x y = x + y`                 | Simple alias, no patterns                   |
| add002  | PASS   | `double x = x + x`                | Single-arg alias                            |
| add003  | PASS   | `const x y = x`                   | Multi-arg, unused second arg                |
| add004  | PASS   | `id x = x`                        | Identity function                           |
| add005  | PASS   | `isZero 0 = True; isZero _ = ...` | Multi-clause with Nat constructor           |
| pat001  | PASS   | `myNot True = False; ...`          | Bool pattern matching                       |
| pat002  | PASS   | `myAnd True True = True; ...`      | Two-arg Bool patterns                       |
| pat003  | PASS   | `fromMaybe def Nothing = def; ...` | constSolvable flag solves return type hole  |
| pat004  | FAIL   | `myFst (x, _) = x`                | Elaboration ordering — see below            |
| pat005  | PASS   | `myLength [] = 0; ...`             | Integer defaulting for numeric literals     |

## Changes Made

### 1. `src/TTImp/ProcessDef.idr` — `synthTypeFromPatterns`

Extracts type information from constructor patterns in function definitions
that lack type signatures. Scans LHS arguments for constructor heads to
determine argument types, and scans RHS for constructor heads to determine
return type.

- `resolveConName`: looks up a constructor name and returns its parent type
- `guessFromPat`: tries to guess a type from a pattern, handling `IAlternative`
  (pair syntax, etc.) by checking alternatives for constructor heads
- `guessFromClauses`: scans all clauses for constructor patterns at a given
  argument position
- `guessAllArgTypes`: builds argument type list from constructor scanning
- `isNumericRHS`: detects numeric literal expressions in RHS (IPrimVal,
  IAlternative with UniqueDefault, fromInteger applications)
- `guessReturnType`: scans RHS of clauses for constructor return types;
  falls back to `Integer` when numeric literals are detected
- `markHoleConstSolvable` / `markSynthHoles`: after processType creates the
  type, walks it to mark all unsolved holes as `constSolvable`
- `buildSynthType`: assembles `_ -> _ -> ... -> RetTy` from gathered info

### 2. `src/Core/Context/Context.idr` — `HoleFlags.constSolvable`

Added `constSolvable : Bool` field to `HoleFlags`. When set, the unifier is
allowed to solve the hole as a constant function even when `patternEnv` fails
(i.e., when metavar arguments include constructors from pattern matching).

This flag is only set by `synthTypeFromPatterns` on holes it creates, so it
does not affect normal metavariable resolution (interface search, implicit
arguments, etc.). This eliminates the 66-regression problem from the previous
untargeted constant-function approach.

### 3. `src/Core/Unify.idr` — `tryConstantSolve`

When `patternEnv` fails for a `constSolvable` hole:
1. Quote the solution and check if `shrink tm none` succeeds (closed term)
2. Run occurs check
3. Build a constant function `\x1 => \x2 => ... => solution` by wrapping
   the closed solution in lambdas matching the metavar's Pi-binder type
4. Install the definition via `addDef` / `removeHole`

### 4. `scripts/rebuild.sh` — Fixed smoke test

- Fixed `set -o pipefail` to detect make failures through `| tee`
- Smoke test now uses `printf` with newlines (Idris requires them)
- Smoke test runs from `/tmp` to avoid ipkg source directory constraint

## Remaining Failure

### pat004: Pair matching — Elaboration ordering

```
myFst (x, _) = x
main : IO ()
main = printLn (myFst (42, "hello"))
Error: Can't solve constraint between: Integer and ?a [no locals in scope]
```

The `IAlternative` handling in `guessFromPat` correctly recognizes pair syntax
and generates `Pair ?a ?b` as the argument type. The `constSolvable` flag on
the return type hole works. However, the constraint `?a ~ ?ret[MkPair ...]`
has an elaboration ordering problem:

1. `unifyBothApps` picks `?a` (zero args) as the hole to solve, not `?ret`
2. The RHS `?ret[MkPair ?a ?b x y]` can't shrink to `Term []` (local vars)
3. The constraint is postponed
4. During `main` elaboration, `printLn` triggers `Show ?a` interface search
   before `fromInteger 42` resolves `?a` to `Integer`
5. The `Show ?a` search fails, and the error is recorded as a `Guess` failure

The `constSolvable` flag on `?ret` is correct, but the constraint never
reaches `?ret` as the hole because the `unifyBothApps` heuristic always
picks `?a`. A fix would require either:
- Teaching `unifyBothApps` to try the other orientation on failure
- Or restructuring how the elaborator processes dependent type parameters
  in the presence of `constSolvable` holes

This is fundamentally an elaboration ordering issue, not a unifier limitation.
