# Progressive Idris2 — Development Notes

## Branch & Remote
- Branch: `progressive-stage1`
- Remote: `fork` → git@github.com:david-hoze/Idris2.git (push here, NOT `origin`)

## Build Commands
```bash
# Rebuild compiler
CC=gcc IDRIS2_BOOT=/home/natanh/.idris2/bin/idris2 PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH" make idris2-exec

# Compile with RefC backend
CC=gcc PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH" build/exec/idris2 --cg refc -o NAME file.idr

# Progressive tests (112/112)
CC=gcc PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH" IDRIS2=/home/natanh/Idris2/build/exec/idris2 bash tests/progressive/run_tests.sh chez

# RefC tests
cd tests && CC=gcc PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH" ./build/exec/runtests /home/natanh/Idris2/build/exec/idris2 --timing --threads 8
```

## Session Protocol
- Commit after milestones, push to `fork` remote
- Kill stale `scheme.exe` processes before rebuilding if you get permission denied on .so/.dll files
- **CRT mismatch fix**: `libidris2_support.dll` MUST be built with `/mingw64/bin/gcc` (links msvcrt.dll), not `/ucrt64/bin/gcc` (links ucrt). Chez Scheme uses msvcrt, so FILE* pointers are incompatible across CRTs. If REPL segfaults in `idris2_writeLine`, rebuild with: `cd support/c && CC=/mingw64/bin/gcc make clean build`

## Documentation (in Claude memory)

Detailed docs are stored in Claude's auto-memory at `~/.claude/projects/C--msys64-home-natanh-Idris2/memory/`:

- **[progressive_state.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/progressive_state.md)** — Progressive typing architecture: type synthesis, constraint inference, HOF analysis, mutual recursion, test results (103/103)
- **[refc_optimizations.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/refc_optimizations.md)** — RefC optimization phases 1-6: runtime bugfixes, self-tail-call loops, enum/double unboxing, constructor reuse, fixnum integers, QTT-informed codegen, pointer tagging scheme
- **[repl_commands.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/repl_commands.md)** — Custom REPL commands (:holes, :defs, :prog), REPL audit findings
- **[key_facts.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/key_facts.md)** — Build environment paths, Chez Scheme setup, known issues
- **[feedback_idris2_pitfalls.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/feedback_idris2_pitfalls.md)** — Parser quirks, type system workarounds, name clashes, deprecations
- **[project_context.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/project_context.md)** — Project context (compiler + WebExtension)
- **[project_circuit_presheaf.md](~/.claude/projects/C--msys64-home-natanh-Idris2/memory/project_circuit_presheaf.md)** — Boolean formula presheaf analysis tool

## Key Architecture Points

### Progressive Typing (src/TTImp/ProcessDef.idr, src/Core/Unify.idr)
- `synthTypeFromPatterns`: generates types from LHS patterns without annotations
- `generaliseType`: turns unsolved metas into Pi binders with auto-implicit constraints
- `SynthesisedType` DefFlag marks inferred types
- Annotation monotonicity: adding annotations never changes runtime behavior

### RefC Backend (src/Compiler/RefC/RefC.idr, support/refc/)
- Pointer tagging: 0b00=heap, 0b01=small int, 0b10=double, 0b11=fixnum Integer
- Self-tail-call optimization: `InSelfTailPosition` emits while/continue loops
- Constructor reuse: `addReuseConstructor` with `idris2_isUnique` runtime check
- QTT codegen: `getLinearArgSet` looks up Rig1 args from GlobalDef.type, skips refcounting
- `Env` record tracks `owned`, `reuseMap`, and `linearVars`
