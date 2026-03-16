# Progressive Idris — Test Results

**85/85 progressive tests passing. 705+ upstream tests, zero regressions.**

## Block 1: Type Synthesis (16/16)

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

## Block 2: Show Inferred Types + Type Generalization (5/5)

| Test      | Status | Description                        | Notes                                      |
|-----------|--------|------------------------------------|---------------------------------------------|
| infer001  | PASS   | `--show-inferred-types` flag       | Displays types for unannotated definitions  |
| gen001    | PASS   | `id' x = x` with Int and String   | Single type param, polymorphic usage        |
| gen002    | PASS   | `const' x y = x` with mixed types | Two type params generalized                 |
| gen003    | PASS   | `myLength` with different element  | Recursive function, list element generalized|
| gen004    | PASS   | `add x y = x + y` (Num a => a)    | Typeclass constraint generalized            |
| gen005    | PASS   | `clamp lo hi x` with nested if     | Ord constraint, case block propagation      |

## Block 3: Annotation Monotonicity (30/30)

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

## Block 3: Propagation (5/5)

| Test     | Status | Description                        |
|----------|--------|------------------------------------|
| prop001  | PASS   | Unannotated calls typed function   |
| prop002  | PASS   | Unannotated uses string concat     |
| prop003  | PASS   | Chain through typed root           |
| prop004  | PASS   | Maybe constructor patterns         |
| prop005  | PASS   | Typed where-clause helper          |

## Block 3: Error on Annotation Conflict (5/5)

| Test     | Status | Expected Error                     |
|----------|--------|------------------------------------|
| err001   | PASS   | `Num String` (String + arithmetic) |
| err002   | PASS   | `Num String` (String return + lit) |
| err003   | PASS   | `Integer/String` mismatch (++)     |
| err004   | PASS   | `Bool/Integer` mismatch (patterns) |
| err005   | PASS   | `Integer/String` at call site      |

## Block 5: Level-Adapted Error Messages (2/2)

| Test       | Status | Description                        |
|------------|--------|------------------------------------|
| errmsg001  | PASS   | CantSolveGoal beginner message     |
| errmsg002  | PASS   | UndefinedName beginner message     |

Beginner-friendly messages activate only for Level 0-1 files (no polymorphic
annotations) that have SynthesisedType definitions with PMDef bodies. Adapted
errors: CantConvert, CantSolveGoal, UndefinedName, UnsolvedHoles, InvalidArgs,
MaybeMisspelling.

## Stress Tests (6/6)

| Test        | Status | Description                             | Compile Time |
|-------------|--------|-----------------------------------------|--------------|
| stress001   | PASS   | 20 unannotated functions                | ~3.5s        |
| stress002   | PASS   | 20 mixed-annotation functions           | ~2.8s        |
| stress003   | PASS   | 10-level nested let bindings            | ~1.7s        |
| stress004   | PASS   | 20 unannotated (monotonicity v0)        | ~3s          |
| stress004v1 | PASS   | 20 half-annotated (monotonicity v1)     | ~3s          |
| stress004v2 | PASS   | 20 fully-annotated (monotonicity v2)    | ~3s          |

## Typed Holes (4/4)

| Test     | Status | Description                        |
|----------|--------|------------------------------------|
| hole001  | PASS   | Typed hole in unannotated function |
| hole002  | PASS   | Hole preserves inferred context    |
| hole003  | PASS   | Hole in where clause               |
| hole004  | PASS   | Hole in let binding                |

## Tutorial (4 stages, identical output)

| Stage  | Annotations              | Output Identical |
|--------|--------------------------|------------------|
| Stage0 | Zero                     | ✓                |
| Stage1 | API boundary             | ✓                |
| Stage2 | Full with polymorphism   | ✓                |
| Stage3 | Dependent types+totality | ✓                |

## Stage 2: Higher-Order Functions (10/10)

| Test      | Status | Description                        | Notes                                      |
|-----------|--------|------------------------------------|---------------------------------------------|
| hof001    | PASS   | `myApply f x = f x`               | Simple application, single HOF arg          |
| hof002    | PASS   | `myMap f [] = []; myMap f (x::xs) = f x :: myMap f xs` | HOF + constructor patterns (IBindVar path) |
| hof003    | PASS   | `compose f g x = f (g x)`         | Multiple HOF args (Implicit path)           |
| hof004    | PASS   | `myFlip f x y = f y x`            | 2-arity HOF, single arg (IBindVar path)     |
| hof005    | PASS   | `myApply f x = f x` with annotated callee | HOF + propagation from typed function |
| hof006    | PASS   | `myApply` with explicit annotation | Monotonicity: annotated version matches     |
| hof007    | PASS   | `myLiftA2 f g h x = f (g x) (h x)` | 3 HOF args (Implicit path)               |
| hof008    | PASS   | `myApply` monotonicity             | Annotated = unannotated output              |
| hof009    | PASS   | `myMap` monotonicity               | Annotated = unannotated output              |
| hof010    | PASS   | `compose` monotonicity             | Annotated = unannotated output              |

## Full Idris 2 Test Suite

Zero regressions on the Idris 2 test suite (705+ tests). The only failures
are pre-existing: `chez014` and `channels009` (Windows-specific).
