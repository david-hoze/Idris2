# Progressive Idris — Implementation State

## Test Results: 16/17 passing

### Block 1: Type Synthesis (15/16)

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
| pat004    | FAIL   | `myFst (x, _) = x`                | Elaboration ordering — see below            |
| pat005    | PASS   | `myLength [] = 0; ...`             | Integer defaulting for numeric literals     |
| case001   | PASS   | `test x = case not x of ...`      | Case expression with Prelude-typed scrutinee|
| let001    | PASS   | `addDouble x y = let s = ...`     | Let binding                                 |
| where001  | PASS   | `sumSq a b = ... where sq x = ...`| Where clause                                |
| multi001  | PASS   | `greet "world" = ...; greet n = .`| String literal patterns                     |
| rec001    | PASS   | `factorial 0 = 1; ...`             | Recursive with numeric patterns             |
| rec002    | PASS   | `fib 0 = 0; fib 1 = 1; ...`       | Multi-clause recursion (fibonacci)          |

### Block 2: Show Inferred Types (1/1)

| Test      | Status | Description                        | Notes                                      |
|-----------|--------|------------------------------------|---------------------------------------------|
| infer001  | PASS   | `--show-inferred-types` flag       | Displays types for unannotated definitions  |

## Block 2 Feature: `--show-inferred-types`

Compiler flag that displays resolved type signatures for functions without
explicit type annotations. Example:

```
$ idris2 --show-inferred-types --check myfile.idr
1/1: Building myfile (myfile.idr)
add : Integer -> Integer -> Integer
myNot : Bool -> Bool
```

### Implementation

- `SynthesisedType` DefFlag added to `Context.idr` (TTC tag 14)
- Flag set in both `lookupOrAddAlias` (alias mechanism) and
  `synthTypeFromPatterns` (multi-clause/constructor patterns)
- `showInferredTypes : Bool` added to `Session` in `Options.idr`
- `--show-inferred-types` CLOpt in `CommandLine.idr`
- `showSynthesisedTypes` function in `ProcessIdr.idr` iterates over
  current-module definitions (firstEntry..nextEntry), filters by
  `SynthesisedType` flag, displays via `displayType` from `Doc.Display`
- Only shown for current module's own definitions, not imports
- Correctly excludes user-annotated definitions

## Block 1 Changes

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

## Known Limitations

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

Fix paths:
- Teach `unifyBothApps` to prefer `constSolvable` holes
- Or restructure dependent type parameter interaction with `constSolvable`

### Higher-order functions

`apply f x = f x` and `compose f g x = f (g x)` require Hindley-Milner
inference to determine that `f` is a function type. This is Block 2 work
(HM generalization).

### Typeclass operations on unresolved types

Functions using `<`, `>`, `compare` etc. on variable arguments fail because
`Ord` search runs before the argument type is resolved from call-site literals.
Functions using `+`, `*` work because `Num` search is handled differently.
