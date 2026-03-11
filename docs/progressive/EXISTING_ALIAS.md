# Task 0.4b — What Idris 2 Already Accepts Without Type Signatures

## The Alias Mechanism

Idris 2 has an existing mechanism in `src/TTImp/ProcessDef.idr` (line 834)
called `lookupOrAddAlias` that accepts **single-clause definitions where all
arguments are simple variable bindings** (not constructor patterns).

It works by:
1. Checking `isAlias` — the LHS must be `f x y z = ...` with all bind variables
2. Generating a "holey type": `_ -> _ -> ... -> _` (each `_` is `Implicit fc False`)
3. Calling `processType` to register the synthesized type
4. Proceeding with normal elaboration

## What Works (PASS)

| Form | Example | Notes |
|------|---------|-------|
| Simple arithmetic | `add x y = x + y` | Variables inferred from `(+)` |
| String concat | `greet name = "Hello, " ++ name` | Inferred as `String -> String` |
| Comparison | `isPositive x = x > 0` | Returns `Bool` |
| Function chain | `double x = x + x; quadruple x = double (double x)` | Type propagation works |
| Lambda in body | `adder x = \y => x + y` | Single clause, vars only |
| Where clause | `square x = x * x` inside `where` | Local defs already inferred |

## What Fails (FAIL) — Gaps to Fill

### Category 1: Multi-clause / Constructor patterns
**Error: "Can't match on X as it must have a polymorphic type"**

| Form | Example |
|------|---------|
| Bool pattern matching | `myNot True = False; myNot False = True` |
| Nat pattern matching | `isZero Z = True; isZero (S _) = False` |
| List pattern matching | `isEmpty [] = True; isEmpty (_ :: _) = False` |
| Maybe pattern matching | `fromMaybe def Nothing = def; fromMaybe _ (Just x) = x` |
| Recursive list | `myLength [] = 0; myLength (_ :: xs) = 1 + myLength xs` |
| Single-clause with ctor | `myNot True = False; myNot _ = True` |

**Root cause**: The alias mechanism requires ALL arguments to be `IBindVar` (plain
variable bindings). Constructor patterns (`True`, `Z`, `[]`, etc.) fail `isAlias`.
Even when we synthesize a holey type for multi-clause defs, the `MatchTooSpecific`
check in `src/TTImp/Elab/Term.idr:323` rejects constructor patterns against
polymorphic argument types.

### Category 2: Higher-order functions
**Error: "Can't solve constraint between ?_ and ?_ -> ?_"**

| Form | Example |
|------|---------|
| Function application | `apply f x = f x` |
| Composition | `compose f g x = f (g x)` |

**Root cause**: The alias mechanism creates `_ -> _ -> _` for `apply f x = f x`.
When elaborating `f x`, it tries to apply `f` (type `_`) to `x` (type `_`), but
can't unify the meta with a function type. The elaborator needs the argument to
have a known function type `?a -> ?b` rather than just a bare metavariable.

### Category 3: Pair/tuple patterns
**Error: "No type declaration for Main.fst"**

| Form | Example |
|------|---------|
| Pair destructuring | `fst (x, _) = x` |

**Root cause**: `(x, _)` in pattern position isn't recognized by `isAlias` (it's
not a plain bind variable), AND it's a single clause so `lookupOrAddAlias` tries
the alias path, fails `isAlias`, then returns `Nothing` → `NoDeclaration` error.

### Category 4: Case expressions in body
**Error: "Can't infer type for case scrutinee"**

| Form | Example |
|------|---------|
| Case expression | `classify x = case x of { 0 => "zero"; ...}` |

**Root cause**: The alias mechanism creates the right type (`_ -> _`), but the
`case` expression needs to know the scrutinee type. Since `x` has an unsolved
metavariable type, case elaboration can't proceed.

### Category 5: Missing typeclass instances
**Error: "Can't find an implementation for Ord Integer"**

| Form | Example |
|------|---------|
| if-then-else with `>` | `myMax x y = if x > y then x else y` |

**Root cause**: The defaulting to `Integer` works for `Num` (arithmetic) but
`Integer` doesn't have an `Ord` instance in the default resolution. The type
needs to be constrained by the typeclass usage.

### Category 6: Let bindings with local definitions
**Error: "Undefined name y"**

| Form | Example |
|------|---------|
| let with local function | `let double y = y + y in ...` |

**Root cause**: `let` binding `double y = y + y` is different from a where clause.
The `y` parameter isn't being properly scoped in the let binding.

## Strategy for Each Gap

1. **Constructor patterns (Cat 1)**: Need to either pre-analyze patterns to
   constrain types, or modify the MatchTooSpecific check for synthesized types.
2. **Higher-order (Cat 2)**: Need to generate function-type metas `?a -> ?b`
   when the variable is used in function position.
3. **Pair patterns (Cat 3)**: Same as Cat 1 — constructor pattern issue.
4. **Case scrutinee (Cat 4)**: May resolve once Cat 1 is solved.
5. **Typeclass defaulting (Cat 5)**: Need auto-implicit inference for constraints.
6. **Let bindings (Cat 6)**: May be a parser/scoping issue, not type inference.
