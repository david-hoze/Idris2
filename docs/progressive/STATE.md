# Progressive Idris — Implementation State

## Test Results: 7/10 passing

| Test    | Status | Description                        | Notes                                      |
|---------|--------|------------------------------------|--------------------------------------------|
| add001  | PASS   | `add x y = x + y`                 | Simple alias, no patterns                  |
| add002  | PASS   | `double x = x + x`                | Single-arg alias                           |
| add003  | PASS   | `const x y = x`                   | Multi-arg, unused second arg               |
| add004  | PASS   | `id x = x`                        | Identity function                          |
| add005  | PASS   | `isZero 0 = True; isZero _ = ...` | Multi-clause with Nat constructor          |
| pat001  | PASS   | `myNot True = False; ...`          | Bool pattern matching                      |
| pat002  | PASS   | `myAnd True True = True; ...`      | Two-arg Bool patterns                      |
| pat003  | FAIL   | `fromMaybe def Nothing = def; ...` | Return type hole unsolved                  |
| pat004  | FAIL   | `fst (x, _) = x`                  | Pair matching — MatchTooSpecific           |
| pat005  | FAIL   | `myLength [] = 0; ...`             | List + Num instance resolution             |

## Changes Made

### 1. `src/TTImp/ProcessDef.idr` — `synthTypeFromPatterns`

Extracts type information from constructor patterns in function definitions
that lack type signatures. Scans LHS arguments for constructor heads to
determine argument types, and scans RHS for constructor heads to determine
return type.

- `guessFromClauses`: scans all clauses for constructor patterns at a given
  argument position
- `guessAllArgTypes`: builds argument type list from constructor scanning
- `guessReturnType`: scans RHS of clauses for constructor return types
- `buildSynthType`: assembles `_ -> _ -> ... -> RetTy` from gathered info

### 2. `src/Core/Unify.idr` — Attempted and reverted

A constant-function solving approach was tried: when `patternEnv` fails
(metavar args contain constructors) and the solution shrinks to `Term []`
(is "closed"), solve the metavar as a constant function ignoring all args.

**Why it was reverted**: The `shrink tm none` check is insufficient.
When a metavar's local variable argument has been *constrained* to a
constructor through unification (e.g., `?m[a]` where `a` was unified with
`()`), the evaluated closure looks identical to a genuine constructor
argument (e.g., `?ret[True]` from a pattern match). The fix incorrectly
solved interface metavars like `?io` in `HasIO ?io` as `\_ => IO ()` instead
of `IO`, causing 66 test regressions.

**Key insight**: By the time `unifyHole` runs, evaluated metavar arguments
that were originally local variables are indistinguishable from genuine
constructor arguments. A correct fix would need to either:
- Mark specific holes as safe for constant-function solving (e.g., only
  return type holes from `synthTypeFromPatterns`)
- Or avoid creating dependent return type holes in the first place

## Remaining Failures

### pat003: Return type hole — `CantSolveEq`

```
fromMaybe def Nothing = def
fromMaybe def (Just x) = x
Error: Can't solve constraint between: Integer and ?_ [locals in scope: def]
```

The return type is polymorphic (`a`), matching the first argument type and
the `Maybe a` type parameter. `guessReturnType` can't extract a type from
variable RHS expressions (`def`, `x`). The return type hole `?ret[def]`
stays unsolved.

The unifier constant-function approach (see above) would solve this but
was reverted due to regressions. A targeted fix is needed — either:
- Improve `guessReturnType` to cross-reference RHS variables with argument
  types (e.g., `def` is arg 0, so return type = type of arg 0)
- Or mark the return type hole as safe for constant-function solving

### pat004: Pair matching — `MatchTooSpecific`

```
fst (x, _) = x
Error: Can't match on (?x, ?_) as it must have a polymorphic type.
```

The tuple syntax `(x, _)` parses as `MkPair x _`. The pattern elaborator
in `Elab/Term.idr` refuses to match a constructor against an argument type
that's still a bare metavariable (`MatchTooSpecific`). The
`synthTypeFromPatterns` pre-scan needs to recognize pair syntax and generate
a `Pair ?a ?b` argument type. Current `guessFromClauses` likely doesn't
handle the desugared pair constructor.

### pat005: Num instance resolution

```
myLength [] = 0
Error: Can't find an implementation for Num ?_.
```

The numeric literal `0` requires a `Num` instance, but the return type is
still an unsolved metavariable at the point where instance search runs.
The `guessReturnType` scan doesn't extract a type from `0` (it's a literal,
not a constructor). Possible fixes:
- Extend `guessReturnType` to infer `Nat` from literal `0` in RHS
- Or use the case-desugaring approach (now viable since the return type
  hole issue is fixed by the unifier change)
