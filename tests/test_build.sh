# Full package builds, run under fakeroot
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

# A source tarball foo-1.tar.gz containing foo-1/README
make_tarball() {
    mkdir foo-1
    echo "read me" > foo-1/README
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
}

test_basic_package() {
    need fakeroot
    write_slkbuild
    assert_rc 0 build_pkg
    assert_contains build.out "Package has been built."
    assert_file foo-1-x86_64-1.txz
    assert_file foo-1-x86_64-1.md5
    md5sum -c foo-1-x86_64-1.md5 > /dev/null || fail "md5 mismatch"
    assert_in_pkg usr/bin/foo
    assert_in_pkg install/slack-desc
    assert_in_pkg usr/src/foo-1/SLKBUILD
    pkg_cat install/slack-desc > desc
    assert_eq "$(wc -l < desc)" 11 "slack-desc line count"
    assert_eq "$(head -n 1 desc)" "foo: foo (test package)"
}

test_package_owned_by_root() {
    need fakeroot
    write_slkbuild
    assert_rc 0 build_pkg
    tar tvf "$(pkg_file)" | awk '{print $2}' | sort -u > owners
    assert_eq "$(cat owners)" "root/root"
}

test_internal_makepkg() {
    need fakeroot
    write_slkbuild "options=('makepkginternal')"
    assert_rc 0 build_pkg
    assert_file foo-1-x86_64-1.txz
    xz -t foo-1-x86_64-1.txz || fail "not a valid xz file"
    assert_in_pkg usr/bin/foo
}

test_package_types() {
    need fakeroot
    for type in tgz tbz txz; do
        write_slkbuild "options=('$type' 'makepkginternal')"
        assert_rc 0 build_pkg
        assert_file foo-1-x86_64-1.$type
        assert_in_pkg usr/bin/foo
    done
}

test_tlz_uses_lzip() {
    need fakeroot lzip
    for mk in makepkginternal ""; do
        [ -z "$mk" ] && [ ! -x /sbin/makepkg ] && continue
        write_slkbuild "options=('tlz' $mk)"
        assert_rc 0 build_pkg
        file foo-1-x86_64-1.tlz | grep -q "lzip compressed" ||
            fail "${mk:-/sbin/makepkg}: not an lzip file"
        lzip -t foo-1-x86_64-1.tlz || fail "${mk:-/sbin/makepkg}: bad lzip file"
    done
}

test_failed_build() {
    need fakeroot
    write_slkbuild "" "    false || return 1"
    assert_rc 2 build_pkg
    assert_contains build.out "build() failed."
    assert_eq "$(pkg_file)" ""
}

test_failed_packaging() {
    need fakeroot
    write_slkbuild
    MAKEPKG=false assert_rc 2 build_pkg
    assert_contains build.out "creating package foo-1-x86_64-1.txz failed"
    assert_not_contains build.out "Package has been built."
    assert_no_file foo-1-x86_64-1.txz
    assert_no_file foo-1-x86_64-1.md5
}

test_failed_compressor_internal_makepkg() {
    need fakeroot
    mkdir bin
    printf '#!/bin/sh\nexit 1\n' > bin/xz
    chmod +x bin/xz
    write_slkbuild "options=('makepkginternal')"
    PATH="$PWD/bin:$PATH" assert_rc 2 build_pkg
    assert_no_file foo-1-x86_64-1.md5
}

test_source_extracted_and_docs_copied() {
    need fakeroot
    make_tarball
    write_slkbuild 'source=("foo-1.tar.gz")
docs=("readme")' '    [ -f $startdir/src/foo-1/README ] || return 1'
    assert_rc 0 build_pkg
    assert_in_pkg usr/doc/foo-1/README
    # local sources are included in the package
    assert_in_pkg usr/src/foo-1/foo-1.tar.gz
}

test_nosrcpack() {
    need fakeroot
    make_tarball
    write_slkbuild 'source=("foo-1.tar.gz")
options=("nosrcpack")'
    assert_rc 0 build_pkg
    assert_not_in_pkg usr/src/foo-1/foo-1.tar.gz
}

test_noextract() {
    need fakeroot
    make_tarball
    write_slkbuild 'source=("foo-1.tar.gz")
options=("noextract")' '    [ ! -e $startdir/src/foo-1 ] || return 1'
    assert_rc 0 build_pkg
}

test_compressed_patches_decompressed() {
    need fakeroot
    for ext in gz bz2 xz; do
        echo "--- a" > fix-$ext.patch
    done
    gzip fix-gz.patch; bzip2 fix-bz2.patch; xz fix-xz.patch
    write_slkbuild 'source=("fix-gz.patch.gz" "fix-bz2.patch.bz2" "fix-xz.patch.xz")' \
'    for p in gz bz2 xz; do
        [ -f $startdir/src/fix-$p.patch ] || return 1
    done'
    assert_rc 0 build_pkg
}

test_strip_binaries() {
    need fakeroot gcc
    printf 'int main(void){return 0;}\n' > hello.c
    write_slkbuild 'source=("hello.c")' \
'    gcc -g -o $startdir/pkg/usr/bin/hello $startdir/src/hello.c'
    assert_rc 0 build_pkg
    file pkg/usr/bin/hello | grep -q "not stripped" && fail "not stripped"
    write_slkbuild 'source=("hello.c")
options=("nostrip")' \
'    gcc -g -o $startdir/pkg/usr/bin/hello $startdir/src/hello.c'
    assert_rc 0 build_pkg
    file pkg/usr/bin/hello | grep -q "not stripped" || fail "stripped"
}

test_strip_binaries_special_names() {
    need fakeroot gcc
    printf 'int main(void){return 0;}\n' > hello.c
    write_slkbuild 'source=("hello.c")' \
'    for name in "my prog" "a:b" plain; do
        gcc -g -o "$startdir/pkg/usr/bin/$name" $startdir/src/hello.c
    done
    gcc -g -shared -fPIC -o "$startdir/pkg/usr/bin/lib x.so" $startdir/src/hello.c'
    assert_rc 0 build_pkg
    for name in "my prog" "a:b" plain "lib x.so"; do
        file "pkg/usr/bin/$name" | grep -q "not stripped" &&
            fail "$name not stripped"
    done
    return 0
}

test_libtool_archives_removed() {
    need fakeroot
    body='    mkdir -p $startdir/pkg/usr/lib64
    echo la > $startdir/pkg/usr/lib64/libfoo.la'
    write_slkbuild "" "$body"
    assert_rc 0 build_pkg
    assert_not_in_pkg usr/lib64/libfoo.la
    write_slkbuild "options=('keepla')" "$body"
    assert_rc 0 build_pkg
    assert_in_pkg usr/lib64/libfoo.la
}

test_empty_doc_dirs_removed() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/usr/doc/$pkgname-$pkgver/html/img'
    assert_rc 0 build_pkg
    assert_not_contains build.out "rmdir"
    assert_no_file pkg/usr/doc
}

test_doc_dirs_with_files_kept() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/usr/doc/$pkgname-$pkgver $startdir/pkg/usr/doc/other
    echo r > $startdir/pkg/usr/doc/other/README'
    assert_rc 0 build_pkg
    assert_no_file pkg/usr/doc/foo-1
    assert_in_pkg usr/doc/other/README
}

test_zero_length_docs_removed() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/usr/doc/$pkgname-$pkgver
    echo r > $startdir/pkg/usr/doc/$pkgname-$pkgver/README
    : > $startdir/pkg/usr/doc/$pkgname-$pkgver/EMPTY'
    assert_rc 0 build_pkg
    assert_in_pkg usr/doc/foo-1/README
    assert_not_in_pkg usr/doc/foo-1/EMPTY
}

test_man_pages() {
    need fakeroot
    write_slkbuild "" '    M=$startdir/pkg/usr/share/man
    mkdir -p $M/man1 $M/man3
    echo a > $M/man1/real.1
    echo z > $M/man1/pre.1
    gzip -9 $M/man1/pre.1
    ln -s real.1 $M/man1/plain.1
    ln -s pre.1.gz $M/man1/both.1.gz
    ln -s pre.1.gz $M/man1/tgtgz.1
    ln -s ../man1/real.1 $M/man3/other.3'
    assert_rc 0 build_pkg
    assert_in_pkg usr/man/man1/real.1.gz
    assert_in_pkg usr/man/man1/pre.1.gz
    assert_not_in_pkg usr/share/man/man1/real.1
    # recreate the symlinks like installpkg would, and check them
    local pkg="$PWD/$(pkg_file)"
    mkdir root
    (cd root && tar xf "$pkg" && sh install/doinst.sh) ||
        fail "doinst.sh failed"
    for link in man1/plain.1.gz man1/both.1.gz man1/tgtgz.1.gz \
                man3/other.3.gz; do
        [ -L root/usr/man/$link ] || fail "$link is not a symlink"
        [ -e root/usr/man/$link ] || fail "$link is a broken symlink"
    done
}

test_man_and_info_dirs_merged() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/usr/man/man1 $startdir/pkg/usr/share/man/man1
    mkdir -p $startdir/pkg/usr/info $startdir/pkg/usr/share/info
    mkdir -p $startdir/pkg/usr/share/foo
    echo a > $startdir/pkg/usr/man/man1/a.1
    echo b > $startdir/pkg/usr/share/man/man1/b.1
    echo a > $startdir/pkg/usr/info/a.info
    echo b > $startdir/pkg/usr/share/info/b.info
    echo d > $startdir/pkg/usr/share/foo/data'
    assert_rc 0 build_pkg
    for f in usr/man/man1/a.1.gz usr/man/man1/b.1.gz \
             usr/info/a.info.gz usr/info/b.info.gz usr/share/foo/data; do
        assert_in_pkg $f
    done
    pkg_list | grep -q -e "usr/man/man/" -e "usr/info/info/" &&
        fail "nested man/info dirs"
    pkg_list | grep -q -e "usr/share/man" -e "usr/share/info" &&
        fail "usr/share/man or usr/share/info still in package"
    return 0
}

test_install_info() {
    need fakeroot
    for dir in usr/info usr/share/info; do
        write_slkbuild "" "    mkdir -p \$startdir/pkg/$dir
    echo i > \$startdir/pkg/$dir/foo.info
    echo d > \$startdir/pkg/$dir/dir"
        assert_rc 0 build_pkg
        assert_in_pkg usr/info/foo.info.gz
        assert_not_in_pkg usr/info/dir
        assert_not_in_pkg usr/info/dir.gz
        pkg_cat install/doinst.sh > doinst.sh
        assert_contains doinst.sh "install-info --info-dir=usr/info usr/info/foo.info "
        assert_not_contains doinst.sh "usr/info/dir"
    done
}

test_install_info_not_duplicated() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/usr/info $startdir/pkg/install
    echo i > $startdir/pkg/usr/info/foo.info
    echo "usr/bin/install-info usr/info/foo.info" > $startdir/pkg/install/doinst.sh'
    assert_rc 0 build_pkg
    pkg_cat install/doinst.sh > doinst.sh
    assert_eq "$(grep -c install-info doinst.sh)" 1 "install-info lines"
}

test_auto_dotnew() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/etc
    echo c > $startdir/pkg/etc/foo.conf'
    assert_rc 0 build_pkg
    assert_in_pkg etc/foo.conf.new
    pkg_cat install/doinst.sh > doinst.sh
    assert_contains doinst.sh "^dotnew etc/foo.conf$"
}

# Files that build() already installed as .new aren't renamed again
test_auto_dotnew_existing_new_file() {
    need fakeroot
    write_slkbuild "" '    mkdir -p $startdir/pkg/etc
    echo a > $startdir/pkg/etc/foo.conf.new
    echo b > $startdir/pkg/etc/bar.conf'
    assert_rc 0 build_pkg
    assert_in_pkg etc/foo.conf.new
    assert_not_in_pkg etc/foo.conf.new.new
    assert_in_pkg etc/bar.conf.new
    local pkg="$PWD/$(pkg_file)"
    mkdir root
    (cd root && tar xf "$pkg" && sh install/doinst.sh) ||
        fail "doinst.sh failed"
    assert_eq "$(cat root/etc/foo.conf)" a
    assert_eq "$(cat root/etc/bar.conf)" b
    assert_no_file root/etc/foo.conf.new
    assert_no_file root/etc/bar.conf.new
}

test_noautodotnew() {
    need fakeroot
    write_slkbuild "options=('noautodotnew')" '    mkdir -p $startdir/pkg/etc
    echo c > $startdir/pkg/etc/foo.conf'
    assert_rc 0 build_pkg
    assert_in_pkg etc/foo.conf
}

# An explicit dotnew=() must not wipe what post_checks added to doinst.sh
test_dotnew_with_info_and_doinst() {
    need fakeroot
    write_slkbuild 'dotnew=("/etc/foo.conf")
doinst() {
    echo custom-doinst
}' '    mkdir -p $startdir/pkg/etc $startdir/pkg/usr/info
    echo c > $startdir/pkg/etc/foo.conf
    echo c > $startdir/pkg/etc/other.conf
    echo i > $startdir/pkg/usr/info/foo.info'
    assert_rc 0 build_pkg
    assert_in_pkg etc/foo.conf.new
    assert_in_pkg etc/other.conf
    pkg_cat install/doinst.sh > doinst.sh
    sh -n doinst.sh || fail "doinst.sh has syntax errors"
    assert_contains doinst.sh "install-info"
    assert_contains doinst.sh "^dotnew etc/foo.conf$"
    assert_contains doinst.sh "custom-doinst"
}

test_dotnew_missing_file() {
    need fakeroot
    write_slkbuild 'dotnew=("etc/missing.conf")'
    assert_rc 2 build_pkg
    assert_contains build.out "missing.conf was not found"
}

test_doinst_runs() {
    need fakeroot
    write_slkbuild 'doinst() {
    ARCHIVE=data.tar
    echo "$pkgname-$pkgver $ARCHIVE lib$LIBDIRSUFFIX $arch" > doinst.result
}'
    assert_rc 0 build_pkg
    pkg_cat install/doinst.sh > doinst.sh
    env -i sh doinst.sh || fail "doinst.sh failed"
    assert_eq "$(cat doinst.result)" "foo-1 data.tar lib64 x86_64"
}

test_doinst_function_keyword_syntax() {
    need fakeroot
    write_slkbuild 'function doinst {
    echo from-doinst
}'
    assert_rc 0 build_pkg
    pkg_cat install/doinst.sh > doinst.sh
    assert_contains doinst.sh "from-doinst"
}

test_douninst() {
    need fakeroot
    write_slkbuild 'douninst() {
    echo "$pkgname-$pkgver" > douninst.result
}'
    assert_rc 0 build_pkg
    assert_in_pkg install/douninst.sh
    pkg_list | grep -q "^var/lib/pkgtools" && fail "var/lib/pkgtools in package"
    pkg_cat install/douninst.sh > douninst.sh
    env -i sh douninst.sh || fail "douninst.sh failed"
    assert_eq "$(cat douninst.result)" "foo-1"
}

test_custom_variables_in_build() {
    need fakeroot
    write_slkbuild '_name=bar
_src_ver=2' '    echo "$_name-$_src_ver" > $startdir/pkg/usr/bin/foo'
    assert_rc 0 build_pkg
    assert_eq "$(cat pkg/usr/bin/foo)" "bar-2"
}

test_rebuild_cleans_previous_build() {
    need fakeroot
    write_slkbuild "" '    echo c > $startdir/pkg/usr/bin/extra'
    assert_rc 0 build_pkg
    write_slkbuild
    assert_rc 0 build_pkg
    assert_not_in_pkg usr/bin/extra
}

test_permissions_normalized() {
    need fakeroot
    mkdir foo-1
    echo r > foo-1/README; chmod 600 foo-1/README
    echo x > foo-1/run.sh; chmod 700 foo-1/run.sh
    chmod 750 foo-1
    tar cf foo-1.tar foo-1
    rm -r foo-1
    write_slkbuild 'source=("foo-1.tar")' '    mkdir -p $startdir/pkg/usr/doc/foo-1
    cp $startdir/src/foo-1/README $startdir/pkg/usr/doc/foo-1/
    chmod 600 $startdir/pkg/usr/doc/foo-1/README
    chmod 700 $startdir/pkg/usr/doc/foo-1'
    assert_rc 0 build_pkg
    assert_eq "$(stat -c %a src/foo-1)" 755 "src dir mode"
    assert_eq "$(stat -c %a src/foo-1/README)" 644 "src file mode"
    tar tvf "$(pkg_file)" usr/doc/foo-1/README | grep -q "^-rw-r--r--" ||
        fail "doc file is not 644"
    tar tvf "$(pkg_file)" usr/doc/foo-1/ | grep -q "^drwxr-xr-x" ||
        fail "doc dir is not 755"
}

# Symlinks may point outside of the build directory, they must not be
# followed when fixing permissions
test_permissions_dont_follow_symlinks() {
    need fakeroot
    mkdir outside
    echo secret > outside/private.key
    chmod 600 outside/private.key
    mkdir t
    ln -s "$PWD/outside" t/link
    tar cf evil.tar t
    rm -r t
    write_slkbuild 'source=("evil.tar")' "    mkdir -p \$startdir/pkg/usr/doc/foo-1
    ln -s $PWD/outside/private.key \$startdir/pkg/usr/doc/foo-1/LICENSE"
    assert_rc 0 build_pkg
    assert_eq "$(stat -c %a outside/private.key)" 600 "file outside mode"
}

test_multiline_custom_variables() {
    need fakeroot
    write_slkbuild '_files=(
    a
    "b c"
)
_text="line 1
line 2"
_path="$SRC/x"
_after=1' '    printf "%s|" "${_files[@]}" "$_text" "$_path" "$_after" > $startdir/pkg/usr/bin/foo'
    assert_rc 0 slkbuild
    bash -n build-foo.sh || fail "build script has syntax errors"
    assert_rc 0 build_pkg
    assert_eq "$(cat pkg/usr/bin/foo)" "a|b c|line 1
line 2|$PWD/src/x|1|"
}

test_custom_functions() {
    need fakeroot
    write_slkbuild '_greet() {
    echo "hello $1" > $startdir/pkg/usr/bin/foo
}
function _second {
    _greet "from $pkgname"
}
notcopied() {
    true
}' '    _second || return 1'
    assert_rc 0 slkbuild
    assert_not_contains build-foo.sh "^notcopied"
    assert_rc 0 build_pkg
    assert_eq "$(cat pkg/usr/bin/foo)" "hello from foo"
}

test_custom_functions_not_taken_from_environment() {
    _fromenv() { true; }
    export -f _fromenv
    write_slkbuild
    assert_rc 0 slkbuild
    assert_not_contains build-foo.sh "_fromenv"
}

# docs=() must use the shallowest match, not whatever find returns last
test_docs_shallowest_match() {
    need fakeroot
    for order in "a/vendored/lib z" "z a/vendored"; do
        rm -rf foo-1 foo-1.tar.gz pkg src
        mkdir foo-1
        echo "MAIN README" > foo-1/README
        echo "lowercase readme" > foo-1/readme
        echo "main changes" > foo-1/ChangeLog
        for d in $order; do
            mkdir -p foo-1/$d
            echo "readme from $d" > foo-1/$d/README
            echo "changes from $d" > foo-1/$d/ChangeLog
        done
        tar czf foo-1.tar.gz foo-1
        rm -r foo-1
        write_slkbuild 'source=("foo-1.tar.gz")
docs=("readme" "changelog")'
        assert_rc 0 build_pkg
        assert_eq "$(cat pkg/usr/doc/foo-1/README)" "MAIN README" "README ($order)"
        assert_eq "$(cat pkg/usr/doc/foo-1/readme)" "lowercase readme" "readme ($order)"
        assert_eq "$(cat pkg/usr/doc/foo-1/ChangeLog)" "main changes" "ChangeLog ($order)"
    done
}

test_docs_only_in_subdirectory() {
    need fakeroot
    mkdir -p foo-1/doc
    echo "doc readme" > foo-1/doc/README
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
    write_slkbuild 'source=("foo-1.tar.gz")
docs=("readme")'
    assert_rc 0 build_pkg
    assert_eq "$(cat pkg/usr/doc/foo-1/README)" "doc readme"
}

test_docs_none_found() {
    need fakeroot
    mkdir foo-1
    echo x > foo-1/main.c
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
    write_slkbuild 'source=("foo-1.tar.gz")
docs=("readme" "changelog")'
    assert_rc 0 build_pkg
    assert_no_file pkg/usr/doc
}

test_docs_zero_length_removed() {
    need fakeroot
    mkdir foo-1
    echo r > foo-1/README
    : > foo-1/NEWS
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
    write_slkbuild 'source=("foo-1.tar.gz")
docs=("readme" "news")'
    assert_rc 0 build_pkg
    assert_in_pkg usr/doc/foo-1/README
    assert_not_in_pkg usr/doc/foo-1/NEWS
}

test_man_pages_hard_links() {
    need fakeroot
    write_slkbuild "" '    M=$startdir/pkg/usr/share/man
    mkdir -p $M/man1 $M/man3
    echo a > $M/man1/a.1
    ln $M/man1/a.1 $M/man1/b.1
    ln $M/man1/a.1 $M/man3/c.3
    echo x > $M/man1/single.1'
    assert_rc 0 build_pkg
    assert_not_contains build.out "other link"
    assert_in_pkg usr/man/man1/a.1.gz
    assert_in_pkg usr/man/man1/single.1.gz
    pkg_list | grep -q -e 'man1/b\.1$' -e 'man3/c\.3$' && fail "uncompressed man page"
    local pkg="$PWD/$(pkg_file)"
    mkdir root
    (cd root && tar xf "$pkg" && sh install/doinst.sh) || fail "doinst.sh failed"
    for page in man1/b.1.gz man3/c.3.gz; do
        [ -L root/usr/man/$page ] || fail "$page is not a symlink"
        assert_eq "$(zcat root/usr/man/$page)" a "$page contents"
    done
}

# Symlinks are turned into doinst.sh code, check that special characters
# survive with both makepkg implementations
test_symlinks_special_characters() {
    need fakeroot
    for mk in makepkginternal ""; do
        [ -z "$mk" ] && [ ! -x /sbin/makepkg ] && continue
        rm -rf root pkg src foo-1-*
        write_slkbuild "options=($mk)" '    cd $startdir/pkg/usr/bin
    echo t > "my target"
    ln -s foo "my foo"
    ln -s "my target" "it'"'"'s (a) \$link;&"
    mkdir -p "$startdir/pkg/usr/share/a dir"
    ln -s ../../bin/foo "$startdir/pkg/usr/share/a dir/link"'
        assert_rc 0 build_pkg
        local pkg="$PWD/$(pkg_file)"
        mkdir root
        (cd root && tar xf "$pkg" && sh install/doinst.sh) > doinst.out 2>&1 ||
            { cat doinst.out; fail "${mk:-makepkg}: doinst.sh failed"; }
        assert_eq "$(readlink "root/usr/bin/my foo")" foo "${mk:-makepkg}: my foo"
        assert_eq "$(readlink "root/usr/bin/it's (a) \$link;&")" "my target" \
            "${mk:-makepkg}: special characters"
        assert_eq "$(readlink "root/usr/share/a dir/link")" ../../bin/foo \
            "${mk:-makepkg}: link in a dir with a space"
    done
}

# docs=() entries are find patterns, they must not be expanded by the shell
test_docs_patterns_and_spaces() {
    need fakeroot
    mkdir -p foo-1/doc
    echo a > foo-1/doc/a.txt
    echo b > foo-1/doc/B.TXT
    echo r > "foo-1/read me"
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
    # would match the pattern if it was expanded in the build directory
    touch notes.txt
    write_slkbuild 'source=("foo-1.tar.gz")
docs=("*.txt" "read me")' '    cd $startdir/src/foo-1/doc'
    assert_rc 0 build_pkg
    assert_file pkg/usr/doc/foo-1/a.txt
    assert_file pkg/usr/doc/foo-1/B.TXT
    assert_file "pkg/usr/doc/foo-1/read me"
    assert_no_file pkg/usr/doc/foo-1/notes.txt
}

test_extract_failure() {
    need fakeroot
    mkdir foo-1
    head -c 100000 /dev/urandom > foo-1/data
    tar czf full.tar.gz foo-1
    rm -r foo-1
    head -c 50000 full.tar.gz > foo-1.tar.gz
    write_slkbuild 'source=("foo-1.tar.gz")'
    assert_rc 2 build_pkg
    assert_contains build.out "Extracting foo-1.tar.gz failed"
    assert_no_file foo-1-x86_64-1.txz
}

# Build a small meson project with the meson template
test_meson_template() {
    need fakeroot meson ninja cc
    mkdir foo-1
    printf "project('foo', 'c')\nexecutable('foo', 'foo.c', install: true)\n" \
        > foo-1/meson.build
    echo 'int main(void) { return 0; }' > foo-1/foo.c
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
    assert_rc 0 slkbuild -g meson
    fill_template
    assert_rc 0 build_pkg
    assert_in_pkg usr/bin/foo
    meson configure src/foo-1/build > options.out
    assert_contains options.out "^ *buildtype  *release "
}

# The build script works in its own directory, wherever it's run from
test_build_script_run_from_another_directory() {
    need fakeroot
    write_slkbuild
    assert_rc 0 slkbuild
    mkdir -p elsewhere/src/keep elsewhere/pkg
    touch elsewhere/src/keep/important
    (cd elsewhere && fakeroot ../build-foo.sh > ../build.out 2>&1) ||
        { cat build.out; fail "build script failed"; }
    assert_file elsewhere/src/keep/important
    assert_no_file elsewhere/foo-1-x86_64-1.txz
    assert_file foo-1-x86_64-1.txz
    assert_in_pkg usr/src/foo-1/SLKBUILD
}

# numjobs given when generating is the default, but it can be overridden
# when running the build script
test_numjobs() {
    need fakeroot
    write_slkbuild '' '    echo $numjobs > $startdir/pkg/usr/bin/numjobs'
    numjobs=3 assert_rc 0 slkbuild
    fakeroot ./build-foo.sh > build.out 2>&1 || fail "build failed"
    assert_eq "$(pkg_cat usr/bin/numjobs)" 3
    numjobs=5 fakeroot ./build-foo.sh > build.out 2>&1 || fail "build failed"
    assert_eq "$(pkg_cat usr/bin/numjobs)" 5
    unset numjobs
    assert_rc 0 slkbuild
    fakeroot ./build-foo.sh > build.out 2>&1 || fail "build failed"
    assert_eq "$(pkg_cat usr/bin/numjobs)" 1
}

# Docs go to usr/doc/$pkgname-$pkgver, like the ones from docs=(). The
# build tools are replaced with stubs that record their arguments.
test_templates_docdir() {
    need fakeroot
    mkdir bin
    for cmd in cmake make musl-gcc; do
        printf '#!/bin/sh\necho "$*" >> "$ARGS_FILE"\n' > bin/$cmd
        chmod +x bin/$cmd
    done
    mkdir foo-1
    cp bin/cmake foo-1/configure
    tar czf foo-1.tar.gz foo-1
    rm -r foo-1
    export ARGS_FILE="$PWD/args"
    while read -r template docdir; do
        rm -f args SLKBUILD
        [ "$template" = "-" ] && template=""
        assert_rc 0 slkbuild -g $template
        fill_template
        PATH="$PWD/bin:$PATH" assert_rc 0 build_pkg
        assert_contains args "$docdir=/usr/doc/foo-1 "
    done <<'EOT'
- --docdir
gconf --docdir
mateconf --docdir
musl --docdir
cmake -DCMAKE_INSTALL_DOCDIR
EOT
}
