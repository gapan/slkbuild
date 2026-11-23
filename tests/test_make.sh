# The Makefile
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

# Copy what the Makefile needs to the current directory
copy_repo() {
    need make txt2tags
    cp -r "$REPO_DIR"/Makefile "$REPO_DIR"/src "$REPO_DIR"/etc \
        "$REPO_DIR"/man .
    rm -f man/slkbuild.8 man/SLKBUILD.5 slkbuild
}

test_make_sysconfdir() {
    copy_repo
    make SYSCONFDIR=/a > make.out 2>&1 || { cat make.out; fail "make failed"; }
    assert_contains slkbuild 'TEMPLATE="/a/slkbuild/'
    # a different SYSCONFDIR later on isn't ignored
    make SYSCONFDIR=/b > make.out 2>&1 || { cat make.out; fail "make failed"; }
    assert_contains slkbuild 'TEMPLATE="/b/slkbuild/'
    # and the source isn't changed
    cmp -s src/slkbuild "$REPO_DIR"/src/slkbuild || fail "src/slkbuild changed"
    make clean > make.out 2>&1
    assert_no_file slkbuild
}

test_make_install_without_make() {
    copy_repo
    make install DESTDIR="$PWD/root" PREFIX=/usr SYSCONFDIR=/c \
        > make.out 2>&1 || { cat make.out; fail "make install failed"; }
    assert_contains root/usr/bin/slkbuild 'TEMPLATE="/c/slkbuild/'
    assert_not_contains root/usr/bin/slkbuild "@sysconfdir@"
    assert_file root/usr/man/man5/SLKBUILD.5
    assert_file root/usr/man/man8/slkbuild.8
    assert_file root/c/slkbuild/SLKBUILD
}
