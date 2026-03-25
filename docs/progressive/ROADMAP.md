# Progressive Idris — Roadmap

Tasks and plans for closing the gap with Python's prototyping experience.

## Completed

### Context Snapshot (prelude.snap)
Serialize prelude Context to binary blob for fast cold start.
- REPL startup: 1.6s -> 0.28s (RefC), 1.2s -> 0.78s (Chez)
- Files: `src/Core/ContextSnapshot.idr`, `src/Idris/Driver.idr`, `src/Idris/REPL.idr`

### RefC Self-Compilation
Compile the Idris2 compiler itself via `--cg refc` to native binary.
- Eliminates ~0.8s Chez Scheme boot overhead
- Build: `LDLIBS="-lws2_32" CC=gcc build/exec/idris2 --cg refc --build idris2.ipkg`

### Progressive Typing (Stages 1-2)
- Stage 1: Unannotated definitions, type synthesis, generalization (75 tests)
- Stage 2: Higher-order function inference (10 tests)
- See `CHANGES.md` for details

### Python Skin
- `def`/`if`/`elif`/`for`/`class` syntax desugaring to TTImp
- See `docs/progressive/GUIDE.md`

### RefC Optimizations (Phases 1-6)
- Self-tail-call loops, enum/double unboxing, constructor reuse, fixnum integers, QTT codegen
- See `docs/progressive/REFC_OPTIMIZATION.md`

## In Progress

### Close the LOC Gap (PythonPrelude)
Reduce Idris boilerplate for Python-style prototyping. Target: Todo app
from 97 lines to under 60.

Planned `PythonPrelude` module providing:
- List indexing: `getAt`, `setAt`, `removeAt`
- Python builtins: `len`, `str`, `range`, `enumerate`
- String ops: `startsWith`, `strip`, `split`, `join`
- IO helpers: `input` (with prompt), `append` (IORef list)

## Planned

### Persistent Compiler Daemon
Keep the compiler process resident for instant reload.
- REPL already caches Prelude between `:l` commands
- Need: wrapper script (`irun`) that keeps REPL alive and pipes `:l`/`:exec`
- Target: <0.3s for file reload after first load

### ZAM VM Crash Fixes
The C-based ZAM VM (`--cg zamc`) segfaults on some programs. The Idris
ZAM interpreter (`--cg zam`) passes all tests, so bytecode is correct.

Debugging plan:
1. Find simplest crashing program
2. Compile VM with `-fsanitize=address` for exact memory error
3. Fix (likely: environment overflow, stack overflow, or serialization mismatch)
4. Target: primes 10K working, then benchmark vs Python

### Startup Parity with Python
Current: 0.28s (RefC + snapshot) vs 0.14s (Python).
Three paths to close the 0.14s gap:
1. Shrink binary (dead code elimination)
2. Lazy snapshot loading (mmap instead of full deserialize)
3. Daemon mode (amortize startup across invocations)
