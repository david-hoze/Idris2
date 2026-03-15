# Progressive Idris — Known Limitations

This documents edge cases that do **not** work without type annotations in
Progressive Idris, along with workarounds.

## 1. Mutual Recursion

**Status**: Does not work without annotations.

Unannotated mutual recursion fails because each function is elaborated
sequentially — when `isEven` is elaborated, `isOdd` has not yet been
defined.

```idris
-- FAILS: Undefined name isOdd
isEven x = if x == 0 then True else isOdd (x - 1)
isOdd x = if x == 0 then False else isEven (x - 1)
```

Even a `mutual` block does not help — Idris 2 still needs forward-declared
type signatures for mutual definitions.

**Workaround**: Add type annotations to all mutually recursive functions.

```idris
mutual
  isEven : Integer -> Bool
  isEven x = if x == 0 then True else isOdd (x - 1)
  isOdd : Integer -> Bool
  isOdd x = if x == 0 then False else isEven (x - 1)
```

## 2. Higher-Order Functions (3+ arguments)

**Status**: Does not work without annotations.

Functions like `apply f x = f x` or `compose f g x = f (g x)` require
Hindley-Milner inference to determine that `f` is a function type. The
progressive type synthesis mechanism works by unifying with concrete
constructor types, not by inferring function types from application.

```idris
-- FAILS: Can't solve constraint between: ?_ and ?_ -> ?_
apply f x = f x

-- FAILS: same reason
compose f g x = f (g x)
```

Two-argument functions that apply their argument work fine because the
alias mechanism handles them. The issue is specifically with inferring
that a parameter has a function type.

**Workaround**: Add type annotations.

```idris
apply : (a -> b) -> a -> b
apply f x = f x
```

## 3. Dependent Pattern Matching (without annotation)

**Status**: Does not work — ambiguous constructors.

When using constructors like `::` that exist in multiple types (List,
Vect, Stream), Idris 2 cannot disambiguate without a type annotation.

```idris
-- FAILS: Ambiguous elaboration (::) could be List, Vect, or Stream
import Data.Vect
myHead (x :: _) = x
```

**Workaround**: Provide the type annotation.

```idris
myHead : Vect (S n) a -> a
myHead (x :: _) = x
```

Note: This is not a limitation of progressive typing per se — even
standard Idris 2 requires disambiguation for overloaded constructors.

## 4. Where Clauses with Constructor Patterns (unannotated parent)

**Status**: Does not work when the parent function is also unannotated.

When both the parent and the where-clause helper use constructor patterns,
type inference can fail due to insufficient type information propagation.

```idris
-- FAILS: type mismatch (List Nat vs String)
process xs = let evens = filter isEven xs in length evens
  where
    isEven Z = True
    isEven (S Z) = False
    isEven (S (S n)) = isEven n
```

**Workaround**: Annotate the parent function.

```idris
process : List Nat -> Nat
process xs = let evens = filter isEven xs in length evens
  where
    isEven Z = True
    isEven (S Z) = False
    isEven (S (S n)) = isEven n
```

## What Works

The following features work **without** type annotations:

| Feature                            | Example                                        |
|------------------------------------|-------------------------------------------------|
| Single-clause functions            | `add x y = x + y`                              |
| Multi-clause pattern matching      | `myNot True = False; myNot False = True`        |
| Recursive functions                | `factorial 0 = 1; factorial n = n * factorial (n-1)` |
| Let/where bindings                 | `f x = let y = x + 1 in y * 2`                 |
| Do notation                        | `greet name = do putStrLn ("Hello, " ++ name)`  |
| Case expressions                   | `f x = case x of True => 1; False => 0`        |
| If-then-else                       | `clamp x = if x < 0 then 0 else x`             |
| Records (with annotated fields)    | `defaultConfig = MkConfig "test" 5`             |
| Interface implementations          | `Show Point where show p = ...`                 |
| Polymorphic functions              | `id' x = x` (generalized to `a -> a`)          |
| Typeclass-constrained functions    | `add x y = x + y` (generalized to `Num a => ...`) |
| Mixed annotation levels            | Some functions annotated, others not            |
| Deeply nested compositions         | `pipeline x = dbl (inc (square x))`             |
