# Progressive Idris — Known Limitations

This documents edge cases that do **not** work without type annotations in
Progressive Idris, along with workarounds.

## 1. ~~Mutual Recursion~~ (RESOLVED)

**Status**: Works without annotations inside `mutual` blocks (Stage 2).

```idris
-- Works: mutual block auto-generates forward declarations
mutual
  isEven 0 = True
  isEven n = isOdd (n - 1)
  isOdd 0 = False
  isOdd n = isEven (n - 1)
```

Note: Bare mutual recursion (without the `mutual` keyword) still requires
type annotations or a `mutual` block.

## 2. Higher-Order Functions — Advanced Patterns

**Status**: Basic HOF works (Stage 2). Some advanced patterns require annotations.

Simple HOFs are fully supported:

```idris
-- All of these work without annotations:
myApply f x = f x
myMap f [] = []; myMap f (x :: xs) = f x :: myMap f xs
compose f g x = f (g x)
myFlip f x y = f y x
```

**Foldr pattern** does not work — the accumulator type and return type
have different numbers of local variables in scope, and the unifier
picks the wrong direction:

```idris
-- FAILS: Can't solve constraint between metas with different scopes
myFoldr f acc [] = acc
myFoldr f acc (x :: xs) = f x (myFoldr f acc xs)
```

**HOF args with concrete return type** constraints also fail — e.g.,
`filter` where `if f x then ...` forces the return type to Bool, but
the HOF type variable is rigid:

```idris
-- FAILS: Can't solve constraint between ?_ -> Bool and Integer -> Bool
myFilter f [] = []
myFilter f (x :: xs) = if f x then x :: myFilter f xs else myFilter f xs
```

**Workaround**: Add type annotations.

```idris
myFoldr : (a -> b -> b) -> b -> List a -> b
myFoldr f acc [] = acc
myFoldr f acc (x :: xs) = f x (myFoldr f acc xs)

myFilter : (a -> Bool) -> List a -> List a
myFilter f [] = []
myFilter f (x :: xs) = if f x then x :: myFilter f xs else myFilter f xs
```

## 3. ~~Ambiguous Constructors~~ (RESOLVED)

**Status**: Works without annotations when constructors are unambiguous in
context (Stage 2).

```idris
-- Works: pair and list constructors resolve without annotation
myFst (x, _) = x
myHead (x :: _) = Just x
myHead [] = Nothing
```

Note: When constructors are genuinely ambiguous (e.g., `::` could be
`List`, `Vect`, or `Stream` after importing `Data.Vect`), a type
annotation is still needed — this is standard Idris 2 behaviour, not a
progressive typing limitation.

## 4. Where Clauses — Advanced Patterns (partially resolved)

**Status**: Most where-clause patterns now work without annotations (Stage 2).
Some complex patterns still require annotations.

Simple and multi-helper where clauses work:

```idris
-- Works: multi-clause pattern matching in where clause
process xs = go xs 0
  where
    go [] acc = acc
    go (x :: rest) acc = go rest (acc + x)

-- Works: multiple helpers in same where block
sumSq xs = helper xs 0
  where
    sq x = x * x
    helper [] acc = acc
    helper (x :: rest) acc = helper rest (acc + sq x)
```

**Still fails**: Where clauses that use `Nat` constructors like `Z`/`S`
with `filter` and other higher-order Prelude functions:

```idris
-- FAILS: complex interaction between where-clause types and Prelude generics
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
| Higher-order application           | `myApply f x = f x`                            |
| HOF + constructor patterns         | `myMap f [] = []; myMap f (x::xs) = f x :: myMap f xs` |
| Function composition               | `compose f g x = f (g x)`                      |
| Argument flipping                  | `myFlip f x y = f y x`                         |
| Mutual recursion (in `mutual`)     | `mutual { isEven 0 = True; ... isOdd 0 = False; ... }` |
| Where + constructor patterns       | `f xs = go xs 0 where go [] acc = acc; go (x::xs) acc = ...` |
| Ambiguous constructors             | `myFst (x, _) = x`; `myHead (x :: _) = Just x`        |
