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

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

PASS=0
FAIL=0
_last_exit=0

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

# run_install [env var assignments (KEY=VALUE) ...]
# Runs install.sh inside the Docker image with the supplied environment,
# prints its output, and returns its exit code.
run_install() {
    # Convert KEY=VALUE arguments into a list of "-e KEY=VALUE" docker flags
    docker_env_flags=""
    for arg in "$@"; do
        docker_env_flags="$docker_env_flags -e $arg"
    done
    output=$(docker run --rm \
        -v "$SCRIPT_DIR/testdata:/home/ext-installer/testdata:ro" \
        $docker_env_flags argocd-extension-installer:test 2>&1)
    _last_exit=$?
    echo "$output" | sed 's/^/    | /'
    return $_last_exit
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
    if [ "$_last_exit" = "0" ]; then
        pass "IGNORE_FAILURE=true: exits 0 when download fails"
    else
        fail "IGNORE_FAILURE=true: exits 0 when download fails" \
             "expected exit code 0, got $_last_exit"
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
    if [ "$_last_exit" != "0" ]; then
        pass "IGNORE_FAILURE=false: exits non-zero when download fails"
    else
        fail "IGNORE_FAILURE=false: exits non-zero when download fails" \
             "expected non-zero exit code, got $_last_exit"
    fi
}

# Verify that the default value of IGNORE_FAILURE is false (i.e. omitting the
# variable behaves the same as setting it to false).
test_ignore_failure_defaults_to_false() {
    run_install \
        EXTENSION_NAME=test-ext \
        EXTENSION_URL=http://127.0.0.1:19999/does-not-exist.tar.gz \
        EXTENSION_VERSION=v0.0.1
    # IGNORE_FAILURE intentionally not set
    if [ "$_last_exit" != "0" ]; then
        pass "IGNORE_FAILURE defaults to false: exits non-zero when download fails"
    else
        fail "IGNORE_FAILURE defaults to false: exits non-zero when download fails" \
             "expected non-zero exit code (default ignore_failure=false), got $_last_exit"
    fi
}

# When a checksums file lists both an extension tarball and a related sidecar
# artifact whose filename contains the tarball name as a substring, validation
# must match the tarball entry exactly.
test_checksum_succeeds_when_sbom_sidecar_present() {
    run_install \
        EXTENSION_NAME=test-ext \
        EXTENSION_URL=file:///home/ext-installer/testdata/extension.tar.gz \
        EXTENSION_CHECKSUM_URL=file:///home/ext-installer/testdata/checksums.txt \
        EXTENSION_VERSION=test \
        IGNORE_FAILURE=false
    if [ "$_last_exit" = "0" ]; then
        pass "checksum validation succeeds when checksums file includes SBOM sidecar"
    else
        fail "checksum validation succeeds when checksums file includes SBOM sidecar" \
             "expected exit code 0, got $_last_exit"
    fi
}

# Verify that the headers in EXTENSION_HTTP_HEADERS_FILE are actually sent on
# the download request. A one-shot busybox nc listener inside the container
# captures the raw request.
test_http_headers_are_sent() {
    output=$(docker run --rm --entrypoint sh argocd-extension-installer:test -c '
        printf "Authorization: Bearer SENTINEL\nAccept: application/octet-stream\n" > /tmp/headers
        { printf "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"; sleep 2; } \
            | nc -l -p 18080 > /tmp/req.txt &
        sleep 1
        EXTENSION_NAME=test-ext \
        EXTENSION_VERSION=v0.0.1 \
        EXTENSION_URL=http://127.0.0.1:18080/extension.tar.gz \
        EXTENSION_HTTP_HEADERS_FILE=/tmp/headers \
        IGNORE_FAILURE=true \
            ./install.sh >/dev/null 2>&1
        wait
        cat /tmp/req.txt
    ' 2>&1)
    echo "$output" | sed 's/^/    | /'
    if echo "$output" | grep -q "Authorization: Bearer SENTINEL" &&
       echo "$output" | grep -q "Accept: application/octet-stream"; then
        pass "EXTENSION_HTTP_HEADERS_FILE: all headers are sent on the download request"
    else
        fail "EXTENSION_HTTP_HEADERS_FILE: all headers are sent on the download request" \
             "request did not contain the configured headers"
    fi
}

# A typo'd or unmounted EXTENSION_HTTP_HEADERS_FILE must fail loudly rather than
# silently falling back to an unauthenticated request.
test_http_headers_file_missing_fails() {
    run_install \
        EXTENSION_NAME=test-ext \
        EXTENSION_URL=file:///home/ext-installer/testdata/extension.tar.gz \
        EXTENSION_VERSION=test \
        IGNORE_FAILURE=false \
        EXTENSION_HTTP_HEADERS_FILE=/nonexistent/headers
    if [ "$_last_exit" != "0" ] && echo "$output" | grep -q "does not exist"; then
        pass "EXTENSION_HTTP_HEADERS_FILE: missing file fails with a clear error"
    else
        fail "EXTENSION_HTTP_HEADERS_FILE: missing file fails with a clear error" \
             "expected non-zero exit and an error naming the missing file, got $_last_exit"
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
