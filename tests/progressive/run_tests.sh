#!/bin/bash
# Progressive Idris test runner
# Finds all .idr files in tests/progressive/, compiles and runs them,
# compares output against .expected files.
# Error tests: if a .error file exists (instead of .expected), the test
# expects compilation to FAIL and checks that the error output contains
# each non-empty line from the .error file.
# Uses Chez Scheme backend.

IDRIS2="${IDRIS2:-$(cd "$(dirname "$0")/../.." && pwd)/build/exec/idris2}"

# Ensure correct Chez Scheme is on PATH (console build, not GUI)
export PATH="/home/natanh/chez/bin:/mingw64/bin:/usr/bin:$PATH"

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
        compile_out=$(cd "$dir" && "$IDRIS2" --no-color --check "$base.idr" 2>&1)
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

    # Compile from the file's directory (Idris2 requires source in source dir)
    compile_out=$(cd "$dir" && "$IDRIS2" --cg chez -o "$base" "$base.idr" 2>&1)
    compile_rc=$?

    if [ $compile_rc -ne 0 ]; then
        echo -e "${RED}FAIL${NC} $base (compilation failed)"
        echo "  $compile_out" | head -5
        FAIL=$((FAIL + 1))
        continue
    fi

    # Run the compiled binary
    run_out=$(cd "$dir" && bash "build/exec/$base" 2>&1)
    run_rc=$?

    # Compare
    expected_out=$(cat "$expected")
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
echo "Progressive tests: $TOTAL total, $PASS passed, $FAIL failed, $SKIP skipped"

if [ $FAIL -gt 0 ]; then
    exit 1
elif [ $TOTAL -eq 0 ]; then
    echo "No tests found."
    exit 0
else
    exit 0
fi
