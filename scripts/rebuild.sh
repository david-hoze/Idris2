#!/bin/bash
# Rebuild the Idris2 compiler from source.
#
# Handles:
#   - Correct Chez Scheme on PATH (console build, not GUI)
#   - DLL locking (copies bootstrap compiler to temp dir)
#   - gcc/make on PATH (MSYS2/MinGW)
#   - Backs up working binary before overwrite
#   - Chez heap OOM: retries final link with larger heap
#
# Usage: bash scripts/rebuild.sh

set -e
set -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHEZ_BIN="/home/natanh/chez/bin"
BOOT_TMP="$(mktemp -d)/idris2_boot"
BACKUP_DIR="$REPO/build/exec_backup"
LOG="$REPO/build/rebuild.log"

export PATH="$CHEZ_BIN:/ucrt64/bin:/usr/bin:$PATH"
export CC=gcc

# Backup the working binary
echo "=== Backing up working compiler ==="
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp "$REPO/build/exec/idris2" "$BACKUP_DIR/"
cp -r "$REPO/build/exec/idris2_app" "$BACKUP_DIR/"

# Copy bootstrap compiler to temp dir (avoids DLL locking)
echo "=== Copying bootstrap compiler ==="
mkdir -p "$BOOT_TMP"
cp "$REPO/build/exec/idris2" "$BOOT_TMP/"
cp -r "$REPO/build/exec/idris2_app" "$BOOT_TMP/"

# Build
echo "=== Building Idris2 ==="
cd "$REPO"
if IDRIS2_BOOT="$BOOT_TMP/idris2" make idris2-exec 2>&1 | tee "$LOG"; then
    :
elif grep -q "out of memory" "$LOG" && [ -f "$REPO/build/exec/idris2_app/compileChez" ]; then
    echo ""
    echo "=== Chez OOM — retrying with larger heap ==="
    cd "$REPO/build/exec/idris2_app"
    if scheme --heap-kilobytes 8388608 --script compileChez 2>&1 | tee -a "$LOG"; then
        cd "$REPO"
        echo "=== Chez recompile succeeded ==="
    else
        cd "$REPO"
        echo "=== Chez recompile FAILED ==="
        cp "$BACKUP_DIR/idris2" "$REPO/build/exec/"
        cp -r "$BACKUP_DIR/idris2_app" "$REPO/build/exec/"
        echo "Restored working compiler. Build log at: $LOG"
        rm -rf "$BACKUP_DIR"
        exit 1
    fi
else
    echo ""
    echo "=== BUILD FAILED — restoring backup ==="
    cp "$BACKUP_DIR/idris2" "$REPO/build/exec/"
    cp -r "$BACKUP_DIR/idris2_app" "$REPO/build/exec/"
    echo "Restored working compiler. Build log at: $LOG"
    rm -rf "$BACKUP_DIR"
    exit 1
fi

# Smoke test: compile a trivial program, not just --version
echo ""
echo "=== Smoke test ==="
printf 'module Main\nmain : IO ()\nmain = printLn 42\n' > /tmp/_idris2_smoke.idr
if (cd /tmp && "$REPO/build/exec/idris2" --check _idris2_smoke.idr 2>/dev/null); then
    echo "Smoke test passed."
    rm -f /tmp/_idris2_smoke.idr
    echo "=== BUILD SUCCEEDED ==="
    "$REPO/build/exec/idris2" --version
    rm -rf "$BACKUP_DIR"
else
    echo "Smoke test FAILED — restoring backup."
    rm -f /tmp/_idris2_smoke.idr
    cp "$BACKUP_DIR/idris2" "$REPO/build/exec/"
    cp -r "$BACKUP_DIR/idris2_app" "$REPO/build/exec/"
    echo "Restored working compiler. Build log at: $LOG"
    rm -rf "$BACKUP_DIR"
    exit 1
fi

# Clean up
rm -rf "$(dirname "$BOOT_TMP")"
