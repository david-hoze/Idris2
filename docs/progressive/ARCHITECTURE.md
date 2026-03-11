# Idris 2 Compilation Pipeline Architecture

## Pipeline Overview

```
Source Code (.idr)
    ↓
[1] PARSING → PDecl (high-level AST)
    ↓
[2] DESUGARING → ImpDecl (TTImp)
    ↓
[3] DECLARATION ROUTING
    ↓
[4] TYPE DECLARATION → type added to context
    ↓
[5] DEFINITION PROCESSING → body added to context
    ↓
[6] ELABORATION → Term (core type theory)
    ↓
[7] UNIFICATION → solve metavariables
    ↓
[8] COMPILATION → CExp (imperative IR)
    ↓
[9] LAMBDA LIFT → top-level defs only
    ↓
[10] ANF → A-normal form
    ↓
[11] BACKEND CODEGEN → JS / Chez / C
```

## Stage Details

### 1. Parsing
- **File**: `src/Idris/Parser.idr`
- **Entry**: `topDecl` (line 86)
- **Input**: Source text
- **Output**: `PDecl` (syntax tree with source locations)
- **Atom parser**: `atom` (line 122)

### 2. Desugaring
- **File**: `src/Idris/Desugar.idr`
- **Entry**: `desugarDecl` (line ~83)
- **Input**: `PDecl`
- **Output**: `ImpDecl` (TTImp — two-level type theory IR)
- **Transforms**: do-notation → bind, operators → precedence, string interpolation,
  tuple/list syntax, bang notation, idiom brackets

### 3. Declaration Routing
- **File**: `src/TTImp/ProcessDecls.idr`
- **Entry**: `processDecl` (line 113)
- Routes: `IClaim` → processType, `IDef` → processDef, `IData` → processData, etc.

### 4. Type Declaration Processing
- **File**: `src/TTImp/ProcessType.idr`
- **Entry**: `processType` (line 136)
- Checks name not already defined (line 158-159, throws `AlreadyDefined`)
- Elaborates type in `InType` mode
- Adds type to context

### 5. Definition Processing
- **File**: `src/TTImp/ProcessDef.idr`
- **Entry**: `processDef` (line 881)
- **CRITICAL**: Line 893-894: `lookupOrAddAlias` finds type; if `Nothing` → `noDeclaration fc n`
- Alias mechanism (line 834): auto-generates type for single-clause `f x y = ...` defs
- After finding type, elaborates each clause via `checkClause`

### 6. Elaboration
- **File**: `src/TTImp/Elab.idr`
- **Entry**: `elabTermSub` (line 88)
- **Input**: `RawImp` (TTImp term) + optional expected type
- **Output**: `Term vars` (core term) + `Glued vars` (type)
- **Modes**: `InType`, `InLHS RigCount`, `InExpr`, `InTransform`

### 7. Unification
- **File**: `src/Core/Unify.idr`
- Solves metavariables by unifying types
- Returns `UnifyResult` with constraints, holes solved
- Called from `checkExp` in `src/TTImp/Elab/Check.idr` (line 772+)

### 8-11. Compilation
- **CExp**: `src/Compiler/CompileExpr.idr` — `toCExp` (line 145)
- **Lambda lift**: `src/Compiler/LambdaLift.idr`
- **ANF**: `src/Compiler/ANF.idr`
- **Backends**: `src/Compiler/ES/Node.idr`, `src/Compiler/Scheme/Chez.idr`, etc.

## Key Locations for Progressive Annotations

### Where type signatures are required
- `src/TTImp/ProcessDef.idr:893-894` — `lookupOrAddAlias` returns Nothing → NoDeclaration

### Where the alias mechanism auto-generates types
- `src/TTImp/ProcessDef.idr:834-874` — single-clause, all-variable-pattern definitions
- `isAlias` (line 818): checks LHS is `f x y z` with all bind variables
- `holeyType` (line 869): generates `_ -> _ -> ... -> _`

### Where implicit arguments are created and solved
- `src/TTImp/BindImplicits.idr:121` — `bindNames` extracts implicit type variables
- `src/TTImp/Elab/ImplicitBind.idr:25` — `mkOuterHole` creates metavariables
- `src/TTImp/Elab/ImplicitBind.idr:61` — `mkPatternHole` for pattern variables

### Where metavariables are created and solved
- Created: `Core/Context.idr` — `newDef` with `Hole` definition
- Solved: `Core/Unify.idr` — unification instantiates metas
- Checked: `Idris/ProcessIdr.idr:91` — `checkDelayedHoles`

### Where MatchTooSpecific fires (poly constraint)
- `src/TTImp/Elab/Term.idr:323` — adds poly constraint during LHS elaboration
- `src/TTImp/Elab/ImplicitBind.idr:496` — `checkPolyConstraint` throws `MatchTooSpecific`
- Condition: `onLHS && not topLevel` — argument positions in patterns

### Where multiplicities are checked
- `src/Core/LinearCheck.idr` — full linear usage analysis
- Called from `processDef` after clause checking

### Where error messages are generated
- `src/Core/Core.idr:156` — `NoDeclaration` constructor
- `src/Idris/Error.idr:565` — `perrorRaw (NoDeclaration fc n)` formatting
