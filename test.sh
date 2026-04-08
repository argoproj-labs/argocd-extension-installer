#!/bin/sh
# test.sh - Integration tests for install.sh
#
# Each test function must start with "test_". The harness below discovers and
# runs all such functions automatically, making it easy to add new tests in
# the future.
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

set -u

PASS=0
FAIL=0
SCRIPT="$(cd "$(dirname "$0")" && pwd)/install.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
    echo "  PASS: $1"
    PASS=$(( PASS + 1 ))
}

fail() {
    echo "  FAIL: $1"
    echo "        $2"
    FAIL=$(( FAIL + 1 ))
}

# run_install <description> [env var assignments ...]
# Runs install.sh with the supplied environment and returns its exit code.
# stdout/stderr from the script are suppressed; set VERBOSE=1 to see them.
run_install() {
    if [ "${VERBOSE:-0}" = "1" ]; then
        env "$@" sh "$SCRIPT"
    else
        env "$@" sh "$SCRIPT" >/dev/null 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# Verify that IGNORE_FAILURE=true (the default) causes the script to exit 0
# even when the extension URL is unreachable, so it never blocks API server
# startup.
test_ignore_failure_true_exits_zero_on_bad_url() {
    run_install \
        EXTENSION_NAME=test-ext \
        EXTENSION_URL=http://127.0.0.1:19999/does-not-exist.tar.gz \
        EXTENSION_VERSION=v0.0.1 \
        IGNORE_FAILURE=true
    actual=$?
    if [ "$actual" = "0" ]; then
        pass "IGNORE_FAILURE=true: exits 0 when download fails"
    else
        fail "IGNORE_FAILURE=true: exits 0 when download fails" \
             "expected exit code 0, got $actual"
    fi
}

# Verify that IGNORE_FAILURE=false causes the script to exit non-zero when
# the extension URL is unreachable, blocking startup as the operator intends.
test_ignore_failure_false_exits_nonzero_on_bad_url() {
    run_install \
        EXTENSION_NAME=test-ext \
        EXTENSION_URL=http://127.0.0.1:19999/does-not-exist.tar.gz \
        EXTENSION_VERSION=v0.0.1 \
        IGNORE_FAILURE=false
    actual=$?
    if [ "$actual" != "0" ]; then
        pass "IGNORE_FAILURE=false: exits non-zero when download fails"
    else
        fail "IGNORE_FAILURE=false: exits non-zero when download fails" \
             "expected non-zero exit code, got 0"
    fi
}

# Verify that the default value of IGNORE_FAILURE is true (i.e. omitting the
# variable behaves the same as setting it to true).
test_ignore_failure_defaults_to_true() {
    run_install \
        EXTENSION_NAME=test-ext \
        EXTENSION_URL=http://127.0.0.1:19999/does-not-exist.tar.gz \
        EXTENSION_VERSION=v0.0.1
    # IGNORE_FAILURE intentionally not set
    actual=$?
    if [ "$actual" = "0" ]; then
        pass "IGNORE_FAILURE defaults to true: exits 0 when download fails"
    else
        fail "IGNORE_FAILURE defaults to true: exits 0 when download fails" \
             "expected exit code 0 (default ignore_failure=true), got $actual"
    fi
}

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

run_all_tests() {
    # Collect all function names that start with "test_"
    tests=$(grep -E '^test_[a-zA-Z0-9_]+\(\)' "$0" | sed 's/().*//')

    echo "Running tests..."
    echo ""

    for t in $tests; do
        echo "[ $t ]"
        $t
    done

    echo ""
    echo "Results: $PASS passed, $FAIL failed"

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

run_all_tests

