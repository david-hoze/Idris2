# Progressive Idris — Future Work

## Stage 2: Higher-Order Function Inference

**Status**: Complete. All 3 target programs compile and run correctly.
10 tests added (85 total progressive tests passing).

### Target Programs (all working)

```idris
-- hof001: Simple application
myApply f x = f x           -- infers (a -> b) -> a -> b

-- hof002: Map (HOF + constructor patterns)
myMap f [] = []
myMap f (x :: xs) = f x :: myMap f xs  -- infers (a -> b) -> List a -> List b

-- hof003: Composition (multiple HOF args)
compose f g x = f (g x)     -- infers (a -> b) -> (c -> a) -> c -> b
```

### How It Works

**Body analysis**: `scanAppsIn` scans clause bodies for applications where
pattern-bound variables appear as function heads. `maxArityFor` computes the
maximum number of explicit arguments each variable is applied to.

**Two-path type generation** (based on HOF arg count):

1. **Single HOF arg** (apply, myMap, myFlip): Uses `IBindVar` names for
   function type domains/codomains, then `prependImplicitPis` adds explicit
   implicit Pi binders at the outer scope. This avoids the Pi-scoped codomain
   problem where inner type metas have extra Pi-bound variables in scope.

2. **Multiple HOF args** (compose): Uses `Implicit` holes for function types.
   This allows flexible cross-arg unification (e.g., g's codomain = f's domain
   in compose), which rigid IBindVar variables cannot provide.

**Key helpers in ProcessDef.idr**:
- `hasHOFUsage` — detects if any pattern variables are used as functions
- `scanAppsIn` / `maxArityFor` — HOF arity analysis
- `mkFuncTypeBindVars` — generates `hof0_0 -> hof0_1` IBindVar types
- `mkFuncTypeImplicit` — generates `_ -> _` Implicit types
- `enhanceWithHOFAnalysis` — replaces bare-hole arg types with function types
- `countHOFEnhanced` — counts HOF-enhanced positions for path selection
- `prependImplicitPis` / `bindVarsToVars` — IBindVar scope management

### Known Limitations

- **foldr pattern** (`myFoldr f acc [] = acc; myFoldr f acc (x::xs) = f x (myFoldr f acc xs)`):
  Fails due to meta-meta unification choosing the wrong direction. The
  accumulator's type meta has fewer locals than the return type meta, and
  the unifier always tries to solve the smaller one first.

- **HOF args with concrete return types** (`myFilter f [] = []; myFilter f (x::xs) = if f x then ...`):
  The `if` expression constrains f's return type to Bool, but with the
  IBindVar path, f's codomain is a rigid type variable that can't be
  unified with the concrete type Bool.

- **Multiple HOF args with arity > 1**: The Implicit path hits Pi-scoped
  codomain issues for arity > 1, and the IBindVar path can't unify
  across different HOF args. Would need shared type variables.

## ~~Stage 3, Task 1: Multiplicity Inference~~ (DONE)

`tightenMultiplicities` infers QTT multiplicities from usage patterns. For each
explicit argument of a synthesised-type definition, it trial-sets the argument
to linear and runs `linearCheck` on normalised clause RHSes. Variables used only
once in linear-compatible positions get Rig1; variables used multiple times or in
unrestricted positions (e.g., inside List `(::)`) stay RigW. See ARCHITECTURE.md.

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

### ~~Mutual Recursion Without Annotations~~ (DONE — Stage 2)

Implemented via auto-generated forward declarations in `processDecl` for
`PMutual` blocks. See ARCHITECTURE.md for details.

### ~~Where-Clause Patterns Without Parent Annotation~~ (DONE — Stage 2)

Resolved via forward-meta solving, same-meta constant solving, and an
invertible bypass in `unifyBothApps`. See ARCHITECTURE.md for details.
Complex Nat+Prelude combos still require annotation.
