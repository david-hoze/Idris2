# Progressive Idris — Stage 1

**Status**: Complete. 75/75 progressive tests passing, zero upstream regressions.

Progressive Idris lets you write Idris 2 code without type annotations and
add them gradually. The compiler infers types for unannotated functions,
generalizes polymorphic types and typeclass constraints, and provides
beginner-friendly error messages.

## Documentation Index

| Document                   | Contents                                       |
|----------------------------|-------------------------------------------------|
| [GUIDE.md](GUIDE.md)      | User guide for the progressive workflow          |
| [TESTS.md](TESTS.md)      | Full test results — 75/75 passing                |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Compiler pipeline, implementation details |
| [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) | What still needs annotations    |
| [FUTURE.md](FUTURE.md)    | Stage 2+ plans (HOF inference, IDE, etc.)        |
| [tutorial/](tutorial/)     | 4-stage tutorial demonstrating progressive workflow |

## Quick Summary

### What works without annotations

- Single and multi-clause functions with pattern matching
- Recursive functions, let/where bindings, case/if expressions
- Polymorphic generalization (`id x = x` → `a -> a`)
- Typeclass constraint inference (`add x y = x + y` → `Num a => a -> a -> a`)
- Type propagation from annotated callees to unannotated callers
- Typed holes in unannotated functions
- REPL auto-display of inferred types + `:addtype` command

### Key invariant: Annotation Monotonicity

Adding a type annotation to working code never changes runtime behavior.
Verified by 30 monotonicity tests (10 groups × 3 versions each).

### Known limitations

1. Mutual recursion — needs type annotations (forward declarations)
2. Higher-order functions (3+ args) — `apply f x = f x` needs annotation
3. Ambiguous constructors — `::` needs disambiguation when Vect imported
4. Where-clause patterns with unannotated parent

### Files modified

See [ARCHITECTURE.md](ARCHITECTURE.md) for the complete list of modified
source files and their roles.

## Build & Test

```bash
# Build compiler
bash scripts/rebuild.sh

# Run progressive tests (75/75)
bash tests/progressive/run_tests.sh

# Run full upstream test suite (705+, zero regressions)
bash scripts/run_full_tests.sh
```
