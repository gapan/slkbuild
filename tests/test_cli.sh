# Command line handling
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

test_version() {
    assert_rc 0 slkbuild -v
    assert_contains slkbuild.out "^slkbuild version: [0-9]"
    assert_rc 0 slkbuild --version
}

test_help_exits_0() {
    assert_rc 0 slkbuild -h
    assert_contains slkbuild.out "Usage: slkbuild"
    assert_rc 0 slkbuild --help
}

test_invalid_option() {
    assert_rc 1 slkbuild -q
    assert_contains slkbuild.out "Incorrect usage"
}

test_stray_argument() {
    write_slkbuild
    assert_rc 1 slkbuild foo
    assert_contains slkbuild.out "Incorrect usage"
    assert_no_file build-foo.sh
}

test_no_slkbuild() {
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "No SLKBUILD found"
}

test_no_option_only_generates() {
    write_slkbuild
    assert_rc 0 slkbuild
    assert_file build-foo.sh
    [ -x build-foo.sh ] || fail "build-foo.sh is not executable"
    assert_no_file pkg
    assert_not_contains build-foo.sh "^clean_dirs$"
}

test_clean_dirs_option() {
    write_slkbuild
    assert_rc 0 slkbuild -c
    assert_contains build-foo.sh "^clean_dirs$"
}

# All options must be honoured, not just the first one
test_combined_options() {
    need fakeroot
    write_slkbuild
    for opts in "-c -x" "-x -c" "-xc" "-X" "--execute --clean-dirs"; do
        rm -rf foo-1-* build-foo*
        assert_rc 0 fakeroot "$SLKBUILD_BIN" $opts > out 2>&1
        [ -n "$(pkg_file)" ] || fail "$opts: no package built"
        assert_file build-foo-1-x86_64-1.log
        assert_no_file pkg
        assert_no_file src
        assert_no_file build-foo.sh
    done
}

test_execute_keeps_dirs() {
    need fakeroot
    write_slkbuild
    assert_rc 0 fakeroot "$SLKBUILD_BIN" -x > out 2>&1
    [ -n "$(pkg_file)" ] || fail "no package built"
    assert_file pkg
    assert_file build-foo.sh
}

test_execute_returns_build_status() {
    need fakeroot
    write_slkbuild "" "    false || return 1"
    assert_rc 2 fakeroot "$SLKBUILD_BIN" -x > out 2>&1
    assert_contains out "build() failed"
}

test_generate_default_template() {
    assert_rc 0 slkbuild -g
    cmp -s SLKBUILD "$REPO_DIR/etc/SLKBUILD" || fail "wrong template"
}

test_generate_prototype_forms() {
    for args in "-g cmake" "-gcmake" "--generate=cmake" "--generate cmake"; do
        rm -f SLKBUILD
        assert_rc 0 slkbuild $args
        cmp -s SLKBUILD "$REPO_DIR/etc/SLKBUILD.cmake" ||
            fail "$args: wrong template"
    done
}

test_generate_unknown_prototype() {
    assert_rc 1 slkbuild -g nosuchthing
    assert_contains slkbuild.out "SLKBUILD.nosuchthing found"
    assert_no_file SLKBUILD
}

test_generate_too_many_arguments() {
    assert_rc 1 slkbuild -g cmake perl
    assert_no_file SLKBUILD
}

# An existing SLKBUILD must only be overwritten if the user says so
test_generate_overwrite_prompt() {
    for answer in '' 'n' 'no' 'maybe\n'; do
        echo "MY WORK" > SLKBUILD
        printf "$answer\n" | "$SLKBUILD_BIN" -g > out 2>&1
        assert_eq "$(cat SLKBUILD)" "MY WORK" "answer '$answer'"
    done
    echo "MY WORK" > SLKBUILD
    "$SLKBUILD_BIN" -g < /dev/null > out 2>&1
    assert_eq "$(cat SLKBUILD)" "MY WORK" "closed stdin"
    echo "MY WORK" > SLKBUILD
    printf 'y\n' | "$SLKBUILD_BIN" -g > out 2>&1
    cmp -s SLKBUILD "$REPO_DIR/etc/SLKBUILD" || fail "'y' didn't overwrite"
}
