#!/bin/bash
# Run the full Idris2 test suite on Windows/MSYS2.
#
# Handles:
#   - Killing scheme.exe processes that hold DLL locks
#   - Correct PATH for Chez Scheme, gcc/make
#
# Usage: bash scripts/run_full_tests.sh

set -e
set -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

export PATH="/home/natanh/chez/bin:/ucrt64/bin:/usr/bin:$PATH"

# Kill any lingering scheme processes that hold DLL locks
echo "=== Killing scheme.exe processes ==="
taskkill //F //IM scheme.exe 2>/dev/null || true
sleep 1

echo "=== Running make test ==="
cd "$REPO"
make test 2>&1 | tee "$REPO/build/test.log"
echo ""
echo "Test log at: $REPO/build/test.log"
