#!/usr/bin/env bash
# tests/test.sh — Unit tests for libfake_rlimit.so
# Run from project root: bash tests/test.sh

set -uo pipefail

LIB=./libfake_rlimit.so
PASS=0; FAIL=0; TESTS=0

# ── Test helpers ─────────────────────────────────────────────

ok()   { PASS=$((PASS+1)); TESTS=$((TESTS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); TESTS=$((TESTS+1)); echo "  ✗ $1"; }
section() { echo ""; echo "── $1 ──"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$desc"
    else
        fail "$desc (expected='$expected', got='$actual')"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc ('$needle' not found)"
    fi
}

summary() {
    echo ""
    echo "════════════════════════════════════"
    echo " ${0##*/}: ${PASS} passed, ${FAIL} failed (${TESTS})"
    echo "════════════════════════════════════"
    [[ $FAIL -eq 0 ]]
}

# ── Pre-flight ───────────────────────────────────────────────

if [[ ! -f "$LIB" ]]; then
    echo "Error: $LIB not found — run 'make' first"
    exit 1
fi

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT


# ── Library structure ────────────────────────────────────────

section "Library structure"

_type=$(file "$LIB" 2>/dev/null || true)
assert_contains "is a shared object" "shared object" "$_type"

_syms=$(nm -D "$LIB" 2>/dev/null || true)
assert_contains "exports prlimit64" "prlimit64" "$_syms"
assert_contains "exports setrlimit" "setrlimit" "$_syms"

_rc=0
LD_PRELOAD="$LIB" /bin/true 2>/dev/null || _rc=$?
assert_eq "loads via LD_PRELOAD" "0" "$_rc"


# ── RLIMIT_AS interception ──────────────────────────────────

section "RLIMIT_AS interception"

cat > "${TESTDIR}/test_shim.c" << 'EOF'
#include <sys/resource.h>

int main(void) {
    struct rlimit rl = { .rlim_cur = 1024, .rlim_max = 1024 };
    if (setrlimit(RLIMIT_AS, &rl) != 0) return 1;

    struct rlimit check;
    getrlimit(RLIMIT_AS, &check);
    if (check.rlim_cur == 1024) return 2;

    struct rlimit rl2 = { .rlim_cur = 512, .rlim_max = 512 };
    if (setrlimit(RLIMIT_NOFILE, &rl2) != 0) return 3;

    return 0;
}
EOF

gcc -o "${TESTDIR}/test_shim" "${TESTDIR}/test_shim.c"

_rc=0
LD_PRELOAD="$(realpath "$LIB")" "${TESTDIR}/test_shim" >/dev/null 2>&1 || _rc=$?

case $_rc in
    0) ok   "RLIMIT_AS blocked, RLIMIT_NOFILE passed through" ;;
    1) fail "setrlimit(RLIMIT_AS) not intercepted (rc=1)" ;;
    2) fail "RLIMIT_AS was applied despite shim (rc=2)" ;;
    3) fail "RLIMIT_NOFILE passthrough broken (rc=3)" ;;
    *) fail "shim test crashed (rc=$_rc)" ;;
esac


# ── Sanity: without shim ────────────────────────────────────

section "Sanity (without shim)"

# The shim may be loaded globally via /etc/ld.so.preload, so libc
# wrappers (setrlimit, prlimit64) are intercepted even here.
# Use syscall(SYS_prlimit64, ...) directly — goes straight to the
# kernel, bypassing any LD_PRELOAD symbol interposition.
cat > "${TESTDIR}/test_no_shim.c" << 'EOF'
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/resource.h>

/* Matches kernel's prlimit64 layout — 64-bit fields on all arches */
struct krlimit64 {
    unsigned long long rlim_cur;
    unsigned long long rlim_max;
};

int main(void) {
    struct krlimit64 before, rl, after;

    /* Raw syscall bypasses any shim */
    syscall(SYS_prlimit64, 0, RLIMIT_AS, (void *)0, &before);

    rl.rlim_cur = 1073741824ULL;   /* 1 GiB */
    rl.rlim_max = before.rlim_max; /* keep max unchanged */

    if (syscall(SYS_prlimit64, 0, RLIMIT_AS, &rl, (void *)0) != 0) {
        write(1, "SKIP", 4);
        return 0;
    }

    syscall(SYS_prlimit64, 0, RLIMIT_AS, (void *)0, &after);
    /* Restore */
    syscall(SYS_prlimit64, 0, RLIMIT_AS, &before, (void *)0);

    if (after.rlim_cur == 1073741824ULL)
        write(1, "APPLIED", 7);
    else
        write(1, "UNEXPECTED", 10);

    return 0;
}
EOF

gcc -o "${TESTDIR}/test_no_shim" "${TESTDIR}/test_no_shim.c"

_rc=0
_result=$("${TESTDIR}/test_no_shim" 2>/dev/null) || _rc=$?

if [[ "$_result" == "APPLIED" || "$_result" == "SKIP" ]]; then
    ok "raw prlimit64 syscall applies normally ($_result)"
else
    fail "raw prlimit64 syscall applies normally (rc=$_rc, got='$_result')"
fi


# ── Summary ──────────────────────────────────────────────────

summary
