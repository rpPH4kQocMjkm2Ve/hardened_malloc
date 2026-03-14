#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

LIB=./libfake_rlimit.so

# ── shim compiled and is a shared library ───────────────
if [[ -f "$LIB" ]]; then ok; else fail "libfake_rlimit.so not found"; fi

if file "$LIB" | grep -q "shared object"; then
    ok
else
    fail "not a shared object"
fi

# ── shim exports prlimit64 ─────────────────────────────
if nm -D "$LIB" | grep -q "prlimit64"; then
    ok
else
    fail "prlimit64 not exported"
fi

# ── shim exports setrlimit ─────────────────────────────
if nm -D "$LIB" | grep -q "setrlimit"; then
    ok
else
    fail "setrlimit not exported"
fi

# ── shim can be loaded via LD_PRELOAD ───────────────────
if LD_PRELOAD="$LIB" /bin/true 2>/dev/null; then
    ok
else
    fail "LD_PRELOAD load failed"
fi

# ── RLIMIT_AS is intercepted (setrlimit returns 0) ─────
# Write a small C test program
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "${TMPDIR}/test_rlimit.c" << 'EOF'
#include <stdio.h>
#include <sys/resource.h>

int main(void) {
    struct rlimit rl = { .rlim_cur = 1024, .rlim_max = 1024 };

    /* RLIMIT_AS should be intercepted — returns 0 without applying */
    int rc_as = setrlimit(RLIMIT_AS, &rl);
    if (rc_as != 0) {
        fprintf(stderr, "setrlimit(RLIMIT_AS) returned %d, expected 0\n", rc_as);
        return 1;
    }

    /* Verify RLIMIT_AS was NOT actually applied */
    struct rlimit check;
    getrlimit(RLIMIT_AS, &check);
    if (check.rlim_cur == 1024) {
        fprintf(stderr, "RLIMIT_AS was applied (should have been blocked)\n");
        return 2;
    }

    /* RLIMIT_NOFILE should pass through normally */
    struct rlimit rl2 = { .rlim_cur = 512, .rlim_max = 512 };
    int rc_nofile = setrlimit(RLIMIT_NOFILE, &rl2);
    if (rc_nofile != 0) {
        fprintf(stderr, "setrlimit(RLIMIT_NOFILE) returned %d, expected 0\n", rc_nofile);
        return 3;
    }

    printf("OK\n");
    return 0;
}
EOF

gcc -o "${TMPDIR}/test_rlimit" "${TMPDIR}/test_rlimit.c"

if LD_PRELOAD="$(realpath "$LIB")" "${TMPDIR}/test_rlimit"; then
    ok
else
    fail "RLIMIT_AS interception test failed"
fi

# ── without shim, setrlimit(RLIMIT_AS) actually applies ─
# (sanity check that the shim is what makes the difference)
cat > "${TMPDIR}/test_no_shim.c" << 'EOF'
#include <stdio.h>
#include <sys/resource.h>

int main(void) {
    struct rlimit rl = { .rlim_cur = 1048576, .rlim_max = 1048576 };
    int rc = setrlimit(RLIMIT_AS, &rl);
    if (rc != 0) {
        /* might fail if unprivileged, that's ok */
        printf("SKIP\n");
        return 0;
    }
    struct rlimit check;
    getrlimit(RLIMIT_AS, &check);
    if (check.rlim_cur == 1048576) {
        printf("APPLIED\n");
        return 0;
    }
    printf("UNEXPECTED\n");
    return 1;
}
EOF

gcc -o "${TMPDIR}/test_no_shim" "${TMPDIR}/test_no_shim.c"
result=$("${TMPDIR}/test_no_shim")
if [[ "$result" == "APPLIED" || "$result" == "SKIP" ]]; then
    ok
else
    fail "sanity check: without shim result=$result"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
