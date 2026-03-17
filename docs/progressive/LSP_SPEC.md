# Progressive Idris — LSP / IDE Mode Specification

This document specifies the changes needed in `idris2-lsp` (and Idris 2's
IDE mode protocol) to support progressive typing features. It is written so
that an LSP implementer can work against it without understanding progressive
compiler internals.

**Prerequisites**: The compiler already provides:
- `SynthesisedType` DefFlag on definitions whose types were inferred (not declared)
- `:addtype <name>` REPL command that prints the inferred type without module prefix
- `--show-inferred-types` CLI flag for batch display
- Level-adapted error messages for progressive modules

---

## 1. Hover: Inferred Type Display

### What it should do

When hovering over a function name, the IDE should distinguish inferred types
from declared types:

```
-- Hovering over unannotated `add`:
(inferred) add : Num a => a -> a -> a

-- Hovering over annotated `add`:
add : Integer -> Integer -> Integer
```

The `(inferred)` prefix tells the user that the type was synthesised by the
compiler and can be made explicit via the "Add type signature" code action.

### What the compiler already provides

The `type-of` IDE command (line 27 of `Protocol/IDE/Command.idr`) looks up a
name and returns its type as a string. The existing `TypeOf` command routes to
`Idris.REPL.process (Check ...)` which calls `showHole` or prints the type.

The `SynthesisedType` flag is stored in `GlobalDef.flags` (see
`Core/Context/Context.idr`). After loading a file, any name's definition can
be checked for this flag via `lookupCtxtExact`.

### What needs to change

**Compiler side** (IDE mode protocol):

Add a new IDE command or extend `type-of` to return metadata about whether
the type was inferred:

Option A — extend the `type-of` response with an extra field:

```
;; Request:
(type-of "add" 3 5)

;; Current response:
(:return (:ok "add : Num a => a -> a -> a") 1)

;; Extended response (add a flag):
(:return (:ok "add : Num a => a -> a -> a" :inferred) 1)
```

Option B — add a new `type-info` command that returns structured data:

```
;; Request:
(type-info "add")

;; Response:
(:return (:ok (:name "add"
               :type "Num a => a -> a -> a"
               :synthesised :True)) 1)
```

**Implementation in `IDEMode/REPL.idr`**:

In `process (TypeOf n loc)`, after looking up the type, also check:

```idris
defs <- get Ctxt
Just gdef <- lookupCtxtExact (UN (mkUserName n)) (gamma defs)
  | Nothing => ... -- name not found
let isSynth = SynthesisedType `elem` gdef.flags
```

Then include `isSynth` in the response.

**LSP side** (`idris2-lsp`):

In the `textDocument/hover` handler:

1. Send `type-of` (or `type-info`) to the compiler
2. Check the `synthesised` flag in the response
3. Format the hover content as markdown:

```json
{
  "contents": {
    "kind": "markdown",
    "value": "```idris\n(inferred) add : Num a => a -> a -> a\n```"
  }
}
```

### Example LSP exchange

Request:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "textDocument/hover",
  "params": {
    "textDocument": { "uri": "file:///home/user/Example.idr" },
    "position": { "line": 2, "character": 0 }
  }
}
```

Response (inferred type):
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "contents": {
      "kind": "markdown",
      "value": "```idris\n(inferred) add : Num a => a -> a -> a\n```\n\n*Type was inferred — use \"Add type signature\" to make it explicit.*"
    },
    "range": {
      "start": { "line": 2, "character": 0 },
      "end": { "line": 2, "character": 3 }
    }
  }
}
```

Response (declared type):
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "contents": {
      "kind": "markdown",
      "value": "```idris\nadd : Integer -> Integer -> Integer\n```"
    },
    "range": {
      "start": { "line": 2, "character": 0 },
      "end": { "line": 2, "character": 3 }
    }
  }
}
```

---

## 2. Code Action: Add Type Signature

### What it should do

When the cursor is on an unannotated definition, offer a code action
"Add inferred type signature" that inserts the type declaration above:

```idris
-- Before:
add x y = x + y

-- After:
add : Num a => a -> a -> a
add x y = x + y
```

### What the compiler already provides

The `:addtype <name>` REPL command (implemented in `Idris/REPL.idr`) formats
the type signature without module prefix, ready to paste into source code.
It uses the same `SynthesisedType` flag to identify candidates.

The compiler knows the source location of each definition via `GlobalDef.location`
(an `FC` value with file, line, and column).

### What needs to change

**Compiler side**:

Add a new IDE command `add-type-signature`:

```
;; Request:
(add-type-signature "add")

;; Response — the formatted type signature string:
(:return (:ok "add : Num a => a -> a -> a") 1)
```

**Implementation in `IDEMode/REPL.idr`**:

```idris
process (AddTypeSignature n)
    = replWrap $ Idris.REPL.process (AddType (UN $ mkUserName n))
```

This requires adding `AddTypeSignature String` to the `IDECommand` type in
`Protocol/IDE/Command.idr`, with SExp serialisation:

```
(add-type-signature "add")
```

And routing it to the existing `AddType` REPL command (`Idris/Syntax.idr`
already has the `AddType` constructor).

**LSP side**:

In the `textDocument/codeAction` handler:

1. For each definition at the cursor position, check if it has `SynthesisedType`
2. If yes, send `add-type-signature` to get the formatted signature
3. Return a code action with a `TextEdit` that inserts the signature

### Example LSP exchange

Request:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "textDocument/codeAction",
  "params": {
    "textDocument": { "uri": "file:///home/user/Example.idr" },
    "range": {
      "start": { "line": 2, "character": 0 },
      "end": { "line": 2, "character": 0 }
    },
    "context": { "diagnostics": [] }
  }
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": [
    {
      "title": "Add inferred type signature",
      "kind": "quickfix",
      "edit": {
        "changes": {
          "file:///home/user/Example.idr": [
            {
              "range": {
                "start": { "line": 2, "character": 0 },
                "end": { "line": 2, "character": 0 }
              },
              "newText": "add : Num a => a -> a -> a\n"
            }
          ]
        }
      }
    }
  ]
}
```

---

## 3. Diagnostic Severity for Holes

### What it should do

Typed holes in progressive (unannotated) code should be reported as
**warnings**, not errors. This reflects the progressive philosophy: holes
are part of the iterative workflow, not blocking failures.

```idris
-- Progressive module (has SynthesisedType definitions):
add x y = ?todo    -- Warning: hole `todo : Num a => a`

-- Standard module (all types declared):
add : Int -> Int -> Int
add x y = ?todo    -- Error: hole `todo : Int` (existing behaviour)
```

### What the compiler already provides

The `Metavariables` IDE command (`(metavariables 0)`) returns a list of
`HoleData` records via `getUserHolesData` in `IDEMode/Holes.idr`. Each
record contains the hole name, type, and context (premises).

The compiler already detects "progressive mode" via
`Idris/Progressive/ErrorLevel.idr`:
- `isProgressiveModule` checks if the namespace contains `SynthesisedType`
  definitions with `PMDef` bodies
- `annotationLevel` computes the annotation level (0–4)

### What needs to change

**Compiler side**:

When reporting holes in IDE mode, include a severity field based on whether
the hole's parent definition has `SynthesisedType`:

Option A — extend the `HoleData` SExp with severity:

```
;; Current hole response:
(:return (:ok ((:name "todo" :type "Num a => a" :context ()))) 1)

;; Extended with severity:
(:return (:ok ((:name "todo" :type "Num a => a" :context () :severity :warning))) 1)
```

Option B — use the existing `Warning` reply type for progressive holes
instead of the `Error` reply type.

**Implementation**: In `Idris/Error.idr` or `IDEMode/REPL.idr`, when
reporting `UnsolvedHoles`:

```idris
-- Check if the hole's parent definition is synthesised
let severity = if isProgressiveHole defs holeName
               then DiagWarning
               else DiagError
```

Where `isProgressiveHole` checks if the enclosing function has
`SynthesisedType` in its flags.

**LSP side**:

In the diagnostic handler, map the severity to LSP `DiagnosticSeverity`:

```json
{
  "range": { "start": { "line": 2, "character": 12 }, "end": { "line": 2, "character": 17 } },
  "severity": 2,
  "source": "idris2",
  "message": "hole `todo : Num a => a`"
}
```

Where severity `2` = Warning (vs `1` = Error).

---

## 4. Inlay Hints (Future)

### What it should do

Show inferred types as ghost text after unannotated definitions:

```idris
add x y = x + y  -- ghost text: : Num a => a -> a -> a
```

Or inline for let bindings:

```idris
let result /* : Integer */ = add 3 4
```

### What the compiler already provides

After loading a file, all `SynthesisedType` definitions are available in
the context with their inferred types. The `--show-inferred-types` flag
already iterates these.

### What needs to change

**Compiler side**:

Add a new IDE command `inferred-types` that returns all synthesised types
in the loaded file:

```
;; Request:
(inferred-types)

;; Response:
(:return (:ok (
  (:name "add" :type "Num a => a -> a -> a" :line 2 :col 0)
  (:name "double" :type "Num a => a -> a" :line 5 :col 0)
)) 1)
```

**Implementation**: Iterate context entries with `SynthesisedType` flag,
format types without module prefix, include source locations.

**LSP side**:

In the `textDocument/inlayHint` handler:

1. Send `inferred-types` after file load
2. For each synthesised type, create an inlay hint at the end of the
   function name on its first clause line

### Example LSP exchange

Request:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "textDocument/inlayHint",
  "params": {
    "textDocument": { "uri": "file:///home/user/Example.idr" },
    "range": {
      "start": { "line": 0, "character": 0 },
      "end": { "line": 20, "character": 0 }
    }
  }
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": [
    {
      "position": { "line": 2, "character": 3 },
      "label": " : Num a => a -> a -> a",
      "kind": 1,
      "paddingLeft": true
    }
  ]
}
```

---

## Summary of Required Changes

### Compiler (Idris 2) changes

| Change | File | Description |
|--------|------|-------------|
| Expose `SynthesisedType` in `type-of` | `IDEMode/REPL.idr` | Check flag, include in response |
| Add `add-type-signature` command | `Protocol/IDE/Command.idr`, `IDEMode/REPL.idr` | Route to `:addtype` REPL logic |
| Hole severity for progressive code | `Idris/Error.idr` or `IDEMode/REPL.idr` | Warning vs Error based on parent flags |
| Add `inferred-types` command (future) | `Protocol/IDE/Command.idr`, `IDEMode/REPL.idr` | List all synthesised types with locations |

### LSP (`idris2-lsp`) changes

| Change | Description |
|--------|-------------|
| Hover: `(inferred)` prefix | Check synthesised flag, prepend prefix |
| Code action: add type signature | Offer quick fix for `SynthesisedType` definitions |
| Diagnostics: hole severity | Map progressive holes to Warning severity |
| Inlay hints (future) | Show inferred types as ghost text |

### Compatibility

All changes are backward-compatible:
- Standard Idris 2 modules (no `SynthesisedType` definitions) behave identically
- Extended IDE protocol responses include new fields that old clients ignore
- New commands are additive — existing commands continue to work unchanged
