# Progressive Typing Tutorial: From Python to Idris

This tutorial demonstrates Idris 2's progressive typing workflow. You start
with zero type annotations — writing code like Python — and incrementally
add types as your understanding of the program deepens. At every stage, the
program compiles and produces identical output.

## The Key Property

**Annotation Monotonicity**: adding a type annotation to a working program
either preserves its behavior exactly, or reveals a type error. It never
silently changes what the program does.

This means you can add types at your own pace, with confidence that each
annotation is a pure improvement — more documentation, more safety, same
behavior.

## Stage 0: Zero Annotations

**File: [Stage0.idr](Stage0.idr)**

Write code like Python. No type signatures at all.

```idris
double x = x * 2

greet name = "Hello, " ++ name ++ "!"

isEmpty [] = True
isEmpty (_ :: _) = False

safeHead def [] = def
safeHead _ (x :: _) = x

factorial 0 = 1
factorial n = n * factorial (n - 1)

sumList [] = 0
sumList (x :: xs) = x + sumList xs
```

The compiler infers types from your code:
- `double` gets `Num a => a -> a` (polymorphic — works for any numeric type)
- `greet` gets `String -> String` (from the `++` operator on strings)
- `isEmpty` gets `List a -> Bool` (from the `[]` and `::` patterns)
- `safeHead` gets `a -> List a -> a` (from the constructor patterns)
- `factorial` gets `Integer -> Integer` (numeric literal patterns default)
- `sumList` gets `List Integer -> Integer` (numeric literal + addition)

You can see inferred types with `--show-inferred-types`.

## Stage 1: Annotate the API Boundary

**File: [Stage1.idr](Stage1.idr)**

Add type signatures to the functions you'd document anyway — the ones other
code calls. Internal helpers stay unannotated. The compiler checks that
your annotations are consistent with the implementation.

```idris
double : Num a => a -> a
double x = x * 2

greet : String -> String
greet name = "Hello, " ++ name ++ "!"

isEmpty : List a -> Bool
isEmpty [] = True
isEmpty (_ :: _) = False
```

What changed: nothing at runtime. The annotations are documentation that the
compiler verifies. If you wrote `double : String -> String`, the compiler
would reject it because `*` requires `Num`.

## Stage 2: Full Annotations with Polymorphism

**File: [Stage2.idr](Stage2.idr)**

Every function has a type signature. Where inference gave you a monomorphic
type (like `sumList : List Integer -> Integer`), you can choose to generalize:

```idris
sumList : Num a => List a -> a
sumList [] = 0
sumList (x :: xs) = x + sumList xs
```

This is strictly more general than what Stage 0 inferred — it works for any
numeric type, not just `Integer`. The original call sites still work because
`Integer` satisfies the `Num` constraint.

## Stage 3: Dependent Types and Totality

**File: [Stage3.idr](Stage3.idr)**

The final stage uses Idris's full type system: totality annotations, explicit
quantifiers, and dependent types. This is where Idris goes beyond what Python
(or Haskell) can express.

```idris
total
isEmpty : List a -> Bool
isEmpty [] = True
isEmpty (_ :: _) = False

total
safeHead : a -> List a -> a
safeHead def [] = def
safeHead _ (x :: _) = x
```

The `total` annotation asks the compiler to prove that the function handles
all cases and always terminates. Not every function can be total (e.g.,
`factorial` recurses on `Integer` with no structural decrease proof), and
that's fine — totality is opt-in.

## Running the Stages

Each stage compiles and runs independently, producing identical output:

```
$ idris2 --cg chez -o stage0 Stage0.idr && ./build/exec/stage0
Hello, Python developer!
42
True
False
42
3628800
15
```

Replace `Stage0.idr` with any other stage — the output is the same.

## The Progressive Workflow

1. **Start with no annotations.** Get your logic right first.
2. **Add types at API boundaries.** The compiler checks consistency.
3. **Generalize where useful.** Turn `Integer` into `Num a => a` when
   you want polymorphism.
4. **Add totality when ready.** Prove your functions handle all cases.

At no point does adding an annotation change what your program does. You
only get more safety, more documentation, and more confidence — never less.
