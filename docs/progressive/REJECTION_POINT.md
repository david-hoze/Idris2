# Where Unannotated Definitions Are Rejected

## The Two Rejection Points

### 1. No Type Declaration (multi-clause or constructor-pattern defs)

**File**: `src/TTImp/ProcessDef.idr`
**Function**: `processDef` (line 881)
**Line**: 893-894

```idris
Just gdef <- lookupOrAddAlias opts nest env fc n cs_in
  | Nothing => noDeclaration fc n
```

**What happens**: `lookupOrAddAlias` tries two things:
1. Look up an existing type declaration in the context
2. For single-clause alias-shaped defs, auto-generate a holey type

If both fail, `noDeclaration` is called, which throws `NoDeclaration fc n`.

**When it triggers**: Multi-clause definitions (`f x = ...; f y = ...`) and
single-clause defs with constructor patterns (`f True = ...`).

### 2. MatchTooSpecific (constructor patterns with inferred types)

**File**: `src/TTImp/Elab/Term.idr`
**Line**: 323

```idris
when (onLHS (elabMode elabinfo) && not (topLevel elabinfo)) $
   do let (argv, argt) = res
      let Just expty = exp
               | Nothing => pure ()
      addPolyConstraint (getFC tm) env argv !(getNF expty) !(getNF argt)
```

**What happens**: During LHS elaboration, when a constructor (like `True`, `Z`, `[]`)
appears in argument position, a "poly constraint" is created. Later, in
`checkPolyConstraint` (src/TTImp/Elab/ImplicitBind.idr:496), if the expected type
is still a metavariable and the actual term is concrete, `MatchTooSpecific` is thrown.

**When it triggers**: Even if we extend `lookupOrAddAlias` to generate holey types
for multi-clause defs, the MatchTooSpecific check prevents constructor patterns
from working against polymorphic types.

## The Existing Alias Mechanism

**File**: `src/TTImp/ProcessDef.idr`
**Lines**: 834-874

The alias mechanism handles the case `lookupOrAddAlias eopts nest env fc n [cl@(PatClause _ lhs _)]`:
- Only matches **single clause** definitions
- `isAlias` (line 818) requires all arguments to be `IBindVar` (plain variables)
- Generates `holeyType`: `IPi _ top Explicit (Just name) (Implicit _ False) $ ...`
- Calls `processType` to register the synthesized type
- Elaboration then proceeds normally

**What it accepts**: `add x y = x + y`, `greet name = "Hello, " ++ name`, etc.
**What it rejects**: `myNot True = False`, `isEmpty [] = True`, `fst (x, _) = x`

## Strategy for Fixing

Two problems to solve:

### Problem 1: Extend lookupOrAddAlias for multi-clause defs
The catch-all at line 876 just does a lookup. It needs to also synthesize types
when multiple clauses are present but no declaration exists.

### Problem 2: Handle MatchTooSpecific for synthesized types
Options:
a. **Pre-analyze patterns**: Look at constructor patterns to determine argument types
   before elaboration. E.g., `True`/`False` → `Bool`, `Z`/`(S _)` → `Nat`.
b. **Suppress poly constraint**: Mark synthesized types and skip the poly constraint
   check for them, allowing pattern matching to drive type inference.
c. **Generate specific types**: Instead of `_ -> _`, generate `Bool -> _` when
   the first clause uses Bool constructors.

Option (a) or (c) seems safest — it gives the elaborator concrete types to work
with, avoiding the need to modify the poly constraint mechanism.
