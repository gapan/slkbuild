#!/bin/bash
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:
#
# Test suite runner for slkbuild.
#
# Usage: tests/run.sh [-v] [PATTERN]
#
# Runs every test_* function in tests/test_*.sh, each one in its own
# subshell and temporary directory. If PATTERN is given, only tests whose
# name matches it (grep -E) are run. With -v, the output of passing tests
# is shown too.

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

VERBOSE=0
if [ "$1" = "-v" ]; then
    VERBOSE=1
    shift
fi
PATTERN="${1:-.}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slkbuild-tests.XXXXXX")" || exit 1
trap 'rm -rf "$WORK_DIR"' EXIT

# Test a copy of slkbuild that uses the templates in etc/ of the repo, so
# that the tracked file doesn't need to have @sysconfdir@ substituted.
SLKBUILD_BIN="$WORK_DIR/slkbuild"
sed "s|@sysconfdir@/slkbuild|$REPO_DIR/etc|g; s|@sysconfdir@|$REPO_DIR/etc|g" \
    "$REPO_DIR/src/slkbuild" > "$SLKBUILD_BIN"
chmod +x "$SLKBUILD_BIN"
export SLKBUILD_BIN

# Make results independent of the host and the caller's environment
export arch=x86_64
unset PKGEXT PKGTYPE MAKEPKG CFLAGS CXXFLAGS numjobs

passed=0; failed=0; skipped=0
failed_tests=()

for file in "$TESTS_DIR"/test_*.sh; do
    tests=$(bash -c ". '$file'; declare -F" | awk '{print $3}' |
            grep '^test_' | grep -E -- "$PATTERN")
    for t in $tests; do
        TEST_DIR="$WORK_DIR/$t"
        mkdir -p "$TEST_DIR"
        output=$(
            cd "$TEST_DIR" || exit 1
            export TEST_DIR
            . "$TESTS_DIR/lib.sh"
            . "$file"
            "$t" 2>&1
        )
        rc=$?
        if [ -f "$TEST_DIR/.skip" ]; then
            echo "SKIP  $t ($(cat "$TEST_DIR/.skip"))"
            skipped=$((skipped + 1))
        elif [ $rc -eq 0 ]; then
            echo "PASS  $t"
            [ $VERBOSE -eq 1 ] && [ -n "$output" ] && echo "$output" | sed 's/^/      /'
            passed=$((passed + 1))
        else
            echo "FAIL  $t"
            echo "$output" | sed 's/^/      /'
            failed=$((failed + 1))
            failed_tests+=("$t")
        fi
    done
done

echo
echo "$passed passed, $failed failed, $skipped skipped"
[ $failed -eq 0 ]
