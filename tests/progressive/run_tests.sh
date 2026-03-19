#!/bin/bash
# Progressive Idris test runner
# Finds all .idr files in tests/progressive/, compiles and runs them,
# compares output against .expected files.
# Error tests: if a .error file exists (instead of .expected), the test
# expects compilation to FAIL and checks that the error output contains
# each non-empty line from the .error file.
#
# Usage: bash run_tests.sh [cg]
#   cg = chez (default), zam, refc, etc.
#   For zam backend, uses --exec main instead of compiling to binary.

CG="${1:-chez}"

IDRIS2_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
IDRIS2="${IDRIS2:-$IDRIS2_DIR/build/exec/idris2}"

# On MSYS2/Windows, the bash launcher fails (no readlink/cygpath).
# Use cmd.exe with the .cmd launcher instead.
IDRIS2_CMD="$IDRIS2_DIR/build/exec/idris2.cmd"
if [ -f "$IDRIS2_CMD" ] && command -v cmd.exe &>/dev/null; then
    # Convert MSYS path to Windows path for cmd.exe
    IDRIS2_WIN=$(cygpath -w "$IDRIS2_CMD" 2>/dev/null || echo "$IDRIS2_CMD")
    run_idris2() {
        # Use temp file to preserve exit code (pipe loses it on MSYS2)
        local tmpf=$(mktemp)
        cmd.exe //C "$IDRIS2_WIN" --no-banner "$@" 2>&1 > "$tmpf"
        local rc=$?
        tr -d '\r' < "$tmpf"
        rm -f "$tmpf"
        return $rc
    }
else
    run_idris2() {
        "$IDRIS2" --no-banner "$@" 2>&1
    }
fi

# Ensure correct Chez Scheme is on PATH (console build, not GUI)
export PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for idr in $(find "$SCRIPT_DIR" -name '*.idr' | sort); do
    TOTAL=$((TOTAL + 1))
    dir=$(dirname "$idr")
    base=$(basename "$idr" .idr)
    expected="$dir/$base.expected"
    error_expected="$dir/$base.error"

    if [ -f "$error_expected" ]; then
        # Error test: compilation should fail
        compile_out=$(cd "$dir" && run_idris2 --no-color --check "$base.idr")
        compile_rc=$?

        if [ $compile_rc -eq 0 ]; then
            echo -e "${RED}FAIL${NC} $base (expected error but compiled successfully)"
            FAIL=$((FAIL + 1))
        else
            # Check that each non-empty line from .error appears in the output
            all_matched=true
            while IFS= read -r line || [[ -n "$line" ]]; do
                [ -z "$line" ] && continue
                if ! echo "$compile_out" | grep -qF "$line"; then
                    all_matched=false
                    echo -e "${RED}FAIL${NC} $base (error output missing: $line)"
                    echo "  Got: $(echo "$compile_out" | head -3)"
                    break
                fi
            done < "$error_expected"

            if [ "$all_matched" = true ]; then
                echo -e "${GREEN}PASS${NC} $base"
                PASS=$((PASS + 1))
            else
                FAIL=$((FAIL + 1))
            fi
        fi

        rm -rf "$dir/build"
        continue
    fi

    if [ ! -f "$expected" ]; then
        echo -e "${YELLOW}SKIP${NC} $idr (no .expected file)"
        SKIP=$((SKIP + 1))
        continue
    fi

    if [ "$CG" = "zam" ] || [ "$CG" = "zamc" ]; then
        # ZAM backend: interpret directly with --exec main (no binary output)
        run_out=$(cd "$dir" && run_idris2 --cg zam "$base.idr" -x main | grep -v '^Warning: compiling hole')
        run_rc=$?
        if [ $run_rc -ne 0 ] && [ -z "$run_out" ]; then
            echo -e "${RED}FAIL${NC} $base (execution failed)"
            FAIL=$((FAIL + 1))
            rm -rf "$dir/build"
            continue
        fi
    else
        # Standard backend: compile to binary, then run
        compile_out=$(cd "$dir" && run_idris2 --cg "$CG" -o "$base" "$base.idr")
        compile_rc=$?

        if [ $compile_rc -ne 0 ]; then
            echo -e "${RED}FAIL${NC} $base (compilation failed)"
            echo "  $compile_out" | head -5
            FAIL=$((FAIL + 1))
            rm -rf "$dir/build"
            continue
        fi

        # Run the compiled binary (try direct exe, fall back to bash wrapper)
        if [ -f "$dir/build/exec/$base.exe" ]; then
            run_out=$(cd "$dir" && "build/exec/$base.exe" 2>&1 | tr -d '\r')
        else
            run_out=$(cd "$dir" && bash "build/exec/$base" 2>&1 | tr -d '\r')
        fi
        run_rc=$?
    fi

    # Compare
    expected_out=$(tr -d '\r' < "$expected")
    if [ "$run_out" = "$expected_out" ]; then
        echo -e "${GREEN}PASS${NC} $base"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $base (output mismatch)"
        echo "  Expected: $(head -1 "$expected")"
        echo "  Got:      $(echo "$run_out" | head -1)"
        FAIL=$((FAIL + 1))
    fi

    # Clean build artifacts
    rm -rf "$dir/build"
done

echo ""
echo "Progressive tests ($CG): $TOTAL total, $PASS passed, $FAIL failed, $SKIP skipped"

if [ $FAIL -gt 0 ]; then
    exit 1
elif [ $TOTAL -eq 0 ]; then
    echo "No tests found."
    exit 0
else
    exit 0
fi
