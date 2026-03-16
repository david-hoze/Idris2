# Progressive Idris — Future Work

## Stage 2: Higher-Order Function Inference

**Status**: Not started. Planned after Stage 1 is stable.

### Problem

Currently, `apply f x = f x` fails because `synthTypeFromPatterns` only
looks at constructor patterns (Z, S, True, False, [], ::, etc.) to
guess argument types. When an argument is used in application position
(`f x`), there's no mechanism to infer that `f` must be a function type.

### Target Programs

```idris
-- hof001: Simple application
apply f x = f x
main : IO ()
main = printLn (apply (+ 1) (the Integer 41))
-- Expected: 42

-- hof002: Map
myMap f [] = []
myMap f (x :: xs) = f x :: myMap f xs
main : IO ()
main = printLn (myMap (+ 10) [1, 2, 3])
-- Expected: [11, 12, 13]

-- hof003: Composition
compose f g x = f (g x)
main : IO ()
main = printLn (compose (* 2) (+ 1) (the Integer 20))
-- Expected: 42
```

### Approach

In `synthTypeFromPatterns` (or during elaboration of synthesised types),
when scanning clause bodies for usage patterns:

- If argument `f` appears as `f x` or `f x y`, generate a function-type
  constraint for f's type: `?f_ty ~ ?a -> ?b` (or `?a -> ?b -> ?c` for 2 args)
- The argument types `?a`, `?b` come from the types of `x`, `y`
- The return type feeds into the function's return type

### Technical Context

The elaborator handles application (IApp) in `src/TTImp/Elab/App.idr` —
it already creates function-type metas during elaboration. The issue is that
`synthTypeFromPatterns` generates `_ -> _` for f's position, which is just a
hole, not a function type.

**Alternative approach**: Instead of pre-analyzing the body, change
`synthTypeFromPatterns` to generate `_ -> _ -> _` as before but ensure
the elaborator's normal application handling creates the right function-type
constraints during elaboration. The problem might be that the synthesised
type's holes aren't being unified properly.

**Debugging strategy**: Add debug output to see what types the elaborator
infers for `f` in `apply f x = f x` and why they don't unify into a
function type. Then fix the root cause.

## Stage 3: IDE Integration

### LSP Inferred Type Hover

When hovering over an unannotated function name, the IDE should show:
```
(inferred) add : Integer -> Integer -> Integer
```

The "(inferred)" prefix distinguishes inferred types from declared types.
Look at `src/Idris/IDEMode/` for the current type-on-hover mechanism.

### LSP "Add Type Signature" Code Action

A code action (quick fix) that inserts the inferred type signature above
an unannotated definition:

```idris
-- Before:
add x y = x + y

-- After clicking "Add inferred type signature":
add : Integer -> Integer -> Integer
add x y = x + y
```

The `:addtype` REPL command (already implemented) provides the backing logic.

## Stage 4: Advanced Features

### Constraint Origin Tracking

When type inference fails due to conflicting constraints, show BOTH
locations that conflict:

```
Type conflict for 'x':
  Used as Integer on line 3: y = x + 1
  Used as String on line 5: z = x ++ " hello"
These uses are incompatible.
```

### Mutual Recursion Without Annotations

Currently requires forward declarations. Could potentially be solved
with a dependency analysis pass that identifies SCCs and synthesizes
types for all members simultaneously.

### Where-Clause Patterns Without Parent Annotation

Currently fails when both parent and where-helper use constructor patterns.
Needs better type propagation between parent and local definitions.
