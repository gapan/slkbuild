# Helpers for the slkbuild test suite. Sourced by tests/run.sh.
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

# Write a SLKBUILD in the current directory. The first argument is added
# before build(), the second is added to the body of build(). build()
# always installs usr/bin/foo, so that the package is never empty.
write_slkbuild() {
    {
        echo '#Packager: Test <test@example.com>'
        echo 'pkgname=foo'
        echo 'pkgver=1'
        echo 'pkgrel=1'
        echo 'slackdesc=("foo (test package)")'
        [ -n "$1" ] && printf '%s\n' "$1"
        echo 'build() {'
        echo '    mkdir -p $startdir/pkg/usr/bin'
        echo '    echo foo > $startdir/pkg/usr/bin/foo'
        [ -n "$2" ] && printf '%s\n' "$2"
        echo '}'
    } > SLKBUILD
}

# Run slkbuild in the current directory. Output goes to slkbuild.out and
# the exit status is returned.
slkbuild() {
    "$SLKBUILD_BIN" "$@" > slkbuild.out 2>&1
}

# Generate the build script and run it under fakeroot. Output goes to
# build.out and the exit status is returned.
build_pkg() {
    slkbuild || { cat slkbuild.out; return 1; }
    fakeroot ./build-foo.sh > build.out 2>&1
}

# The package created by build_pkg (any extension)
pkg_file() {
    ls foo-1-*-1.t?z foo-1-*-1.tbr 2>/dev/null | head -n 1
}

# List the files in the package
pkg_list() {
    tar tf "$(pkg_file)"
}

# Print a file from the package
pkg_cat() {
    tar xOf "$(pkg_file)" "$1"
}

need() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || skip "$cmd not found"
    done
}

skip() {
    echo "$1" > "$TEST_DIR/.skip"
    exit 0
}

fail() {
    echo "FAIL: $*"
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "${3:-values differ}: expected '$2', got '$1'"
}

assert_rc() {
    local expected="$1"; shift
    "$@"
    local rc=$?
    [ "$rc" = "$expected" ] || fail "'$*' exited with $rc, expected $expected"
}

assert_contains() {
    grep -q -e "$2" "$1" 2>/dev/null ||
        fail "'$1' does not contain '$2'"
}

assert_not_contains() {
    ! grep -q -e "$2" "$1" 2>/dev/null ||
        fail "'$1' contains '$2'"
}

assert_file() {
    [ -e "$1" ] || fail "'$1' does not exist"
}

assert_no_file() {
    [ ! -e "$1" ] || fail "'$1' exists"
}

assert_in_pkg() {
    pkg_list | grep -q -x -e "$1" || fail "'$1' not in package"
}

assert_not_in_pkg() {
    ! pkg_list | grep -q -x -e "$1" || fail "'$1' is in package"
}
