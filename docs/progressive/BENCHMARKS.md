# Progressive Idris vs Python — Benchmarks

Measuring the prototyping feedback loop: edit a file, run it, see output.

## REPL Startup (`:q` immediately)

| Configuration | Time | vs Python |
|---|---|---|
| Python | 0.14s | 1.0x |
| Idris2 RefC + snapshot | 0.28s | 2.0x |
| Idris2 Chez + snapshot | 0.78s | 5.6x |
| Idris2 Chez cold | 1.18s | 8.4x |
| Idris2 RefC cold | 1.56s | 11.1x |

## Edit-to-Output: Primes (N=10,000)

| | Wall clock | vs Python |
|---|---|---|
| Python | 0.14s | 1.0x |
| Idris2 RefC `--exec` | 0.61s | 4.3x |
| Idris2 Chez `--exec` | 1.57s | 11.2x |

## Edit-to-Output: Todo App (startup + 5 commands)

| | Wall clock | vs Python |
|---|---|---|
| Python | 0.15s | 1.0x |
| Idris2 RefC `--exec` | 0.76s | 5.1x |
| Idris2 Chez `--exec` | 1.88s | 12.5x |

## Lines of Code

| App | Python | Idris2 |
|---|---|---|
| Todo | 51 | 97 |
| Primes | 23 | 33 |

## RefC `--exec` Time Breakdown (primes 10k)

| Phase | Time | % |
|---|---|---|
| Binary startup + init | ~0.20s | 36% |
| Load snapshot (prelude) | 0.12s | 21% |
| Loading main file (buildDeps + typecheck) | 0.17s | 31% |
| Compile to Chez scheme | 0.07s | 12% |
| **Total** | **0.55s** | |

## Optimizations Applied

### Context Snapshot (prelude.snap)
Serializes the fully-loaded prelude Context to a 2.6MB binary blob after
first load. Subsequent starts deserialize instead of reading ~40 individual
TTC files. Saves ~1.3s on Chez, ~1.3s on RefC.

### RefC Native Binary
Self-compiles the Idris2 compiler to C via `--cg refc`, producing a 27MB
native executable. Eliminates the ~0.8s Chez Scheme boot overhead.

## Remaining Bottlenecks (for Python parity)

1. **Binary startup** (~0.20s) — 27MB executable cold-loading + GMP/runtime init.
   Potential fix: dead code elimination, split into launcher + shared lib.
2. **Snapshot deserialization** (~0.12s) — reading 2.6MB blob, rebuilding NameMaps.
   Potential fix: mmap-based lazy loading.
3. **File loading** (~0.17s) — `buildDeps` TTC checks + type checking.
   Potential fix: file-level snapshots (already prototyped in REPL.idr).

## How to Reproduce

```bash
# Build RefC binary
LDLIBS="-lws2_32" CC=gcc PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH" \
  build/exec/idris2 --cg refc --build idris2.ipkg

# REPL startup benchmark
time (echo ":q" | PATH="/ucrt64/bin:/usr/bin:$PATH" ./build/exec/idris2.exe --no-banner --no-colour)

# --exec benchmark
time PATH="/ucrt64/bin:/usr/bin:$PATH" ./build/exec/idris2.exe --no-banner --exec main scratch/primes10k.idr

# Python baseline
time python3 scratch/primes.py 10000
```
