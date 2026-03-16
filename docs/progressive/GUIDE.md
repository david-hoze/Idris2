# Progressive Idris — User Guide

Progressive Idris lets you write Idris 2 code without type annotations and
add them gradually as your program grows. The compiler infers types for
unannotated functions, generalizes them where possible, and gives you
beginner-friendly error messages while you're learning.

## 1. Quick Start

Write a file called `hello.idr`:

```idris
module Main

greet name = "Hello, " ++ name ++ "!"

main : IO ()
main = putStrLn (greet "world")
```

Compile and run:

```
$ idris2 --cg chez -o hello hello.idr
$ ./build/exec/hello
Hello, world!
```

Notice that `greet` has **no type annotation** — the compiler figures out
that it takes a `String` and returns a `String`.

## 2. The Progressive Workflow

The recommended workflow is:

1. **Write** — Start with no annotations. Focus on what your code does.
2. **Infer** — Use `--show-inferred-types` to see what the compiler inferred.
3. **Annotate** — Add annotations when you want to document intent, catch bugs,
   or use advanced features.
4. **Repeat** — As you learn more Idris, add more annotations.

You can check inferred types at any time:

```
$ idris2 --show-inferred-types --check hello.idr
Inferred type for greet: String -> String
```

## 3. What Works Without Annotations

### Simple functions

```idris
add x y = x + y           -- inferred: Num a => a -> a -> a
double x = x + x          -- inferred: Num a => a -> a
```

### Pattern matching

```idris
myNot True = False
myNot False = True         -- inferred: Bool -> Bool

myLength [] = 0
myLength (_ :: xs) = 1 + myLength xs  -- inferred: List a -> Integer
```

### Recursion

```idris
factorial 0 = 1
factorial n = n * factorial (n - 1)   -- inferred: Integer -> Integer

fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)    -- inferred: Integer -> Integer
```

### Let and where bindings

```idris
sumOfSquares a b = sq a + sq b
  where sq x = x * x      -- inferred: Num a => a -> a -> a
```

### Do notation

```idris
greet name = do
  putStrLn ("Hello, " ++ name)
  putStrLn "How are you?"
```

### Higher-order functions

```idris
myApply f x = f x           -- inferred: (a -> b) -> a -> b
compose f g x = f (g x)     -- inferred: (a -> b) -> (c -> a) -> c -> b
myFlip f x y = f y x        -- inferred: (a -> b -> c) -> b -> a -> c

-- Works with constructor patterns too:
myMap f [] = []
myMap f (x :: xs) = f x :: myMap f xs  -- inferred: (a -> b) -> List a -> List b
```

### If-then-else and case expressions

```idris
clamp lo hi x = if x < lo then lo else if x > hi then hi else x
-- inferred: Ord a => a -> a -> a -> a
```

### Mixed annotation levels

You can annotate some functions and leave others unannotated in the same file.
Adding annotations never changes program behavior:

```idris
inc x = x + 1              -- unannotated
double x = x + x           -- unannotated
pipeline : Integer -> Integer   -- annotated
pipeline x = double (inc x)
```

## 4. Adding Annotations

Annotations serve as documentation and catch type errors early. The
**monotonicity guarantee** means adding an annotation never changes
your program's behavior — it only makes the types more specific.

### Stage 0 — No annotations

```idris
add x y = x + y
double x = add x x
```

### Stage 1 — Annotate the API boundary

```idris
add x y = x + y
double : Integer -> Integer
double x = add x x
```

### Stage 2 — Annotate everything

```idris
add : Integer -> Integer -> Integer
add x y = x + y
double : Integer -> Integer
double x = add x x
```

All three stages produce identical compiled code.

## 5. Pattern Matching

Multi-clause functions with constructor patterns work automatically:

```idris
-- Bool patterns
myAnd True True = True
myAnd _ _ = False

-- Maybe patterns
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x

-- Numeric literal patterns
isZero 0 = True
isZero _ = False
```

The compiler desugars multi-clause definitions into single-clause
functions with `case` expressions, then infers the type from the
constructor patterns.

## 6. Known Limitations

Some features still require type annotations:

| Feature                    | Why                                      | Workaround              |
|----------------------------|------------------------------------------|-------------------------|
| Mutual recursion           | Forward references need declarations     | Add type signatures     |
| foldr/filter patterns      | Unifier limitation with multi-arg HOFs   | Add type signatures     |
| Ambiguous constructors     | `::` could be List, Vect, or Stream      | Add type signature      |
| Where-clause patterns      | Needs annotated parent for context       | Annotate parent function|

See `KNOWN_LIMITATIONS.md` for detailed examples and error messages.

## 7. Comparison with Standard Idris 2

| Feature                        | Standard Idris 2          | Progressive Idris        |
|--------------------------------|---------------------------|--------------------------|
| Type annotations               | Required for all functions | Optional                 |
| Multi-clause without annotation| Error                     | Works (case desugaring)  |
| Typeclass constraints          | Must be declared          | Inferred automatically   |
| Polymorphism                   | Must use type variables   | Inferred automatically   |
| Error messages                 | Technical (Level 2+)      | Beginner-friendly (Level 0-1) |
| Typed holes (`?name`)          | Supported                 | Supported                |
| Dependent types                | Full support              | Requires annotations     |
| Totality checking              | Full support              | Requires annotations     |

Progressive Idris is a **superset** of standard Idris 2 — all valid Idris 2
programs compile identically. The progressive features only activate when
unannotated definitions are present.
