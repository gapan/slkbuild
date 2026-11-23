# Contents of the generated build script
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

test_generated_script_syntax() {
    write_slkbuild 'source=("a.patch")
docs=("README")
dotnew=("etc/foo.conf")
doinst() {
    echo hi
}
douninst() {
    echo bye
}'
    touch a.patch
    assert_rc 0 slkbuild
    bash -n build-foo.sh || fail "build-foo.sh has syntax errors"
}

test_variables() {
    write_slkbuild
    assert_rc 0 slkbuild
    assert_contains build-foo.sh "^pkgname=foo$"
    assert_contains build-foo.sh "^pkgver=1$"
    assert_contains build-foo.sh "^pkgrel=1$"
    assert_contains build-foo.sh "^arch=x86_64$"
    assert_contains build-foo.sh '^export LIBDIRSUFFIX="64"$'
    assert_contains build-foo.sh "^#Packager: Test <test@example.com>$"
}

test_default_flags() {
    write_slkbuild
    assert_rc 0 slkbuild
    assert_contains build-foo.sh '^export CFLAGS="-O2 -fPIC"$'
    assert_contains build-foo.sh '^export CXXFLAGS="-O2 -fPIC"$'
    assert_contains build-foo.sh '^export SLKCFLAGS="-O2 -fPIC"$'
}

test_cflags_also_used_for_cxxflags() {
    write_slkbuild 'CFLAGS="-O1"'
    assert_rc 0 slkbuild
    assert_contains build-foo.sh '^export CFLAGS="-O1"$'
    assert_contains build-foo.sh '^export CXXFLAGS="-O1"$'
}

test_cxxflags_set_separately() {
    write_slkbuild 'CFLAGS="-O1"
CXXFLAGS="-O3"'
    assert_rc 0 slkbuild
    assert_contains build-foo.sh '^export CFLAGS="-O1"$'
    assert_contains build-foo.sh '^export CXXFLAGS="-O3"$'
}

test_arch_i586_flags() {
    write_slkbuild
    arch=i586 assert_rc 0 slkbuild
    assert_contains build-foo.sh "^arch=i586$"
    assert_contains build-foo.sh '^export CFLAGS="-O2 -march=i586 -mtune=i686"$'
    assert_contains build-foo.sh '^export LIBDIRSUFFIX=""$'
}

test_custom_variables() {
    write_slkbuild '_srcname=foobar
_src_ver=2
_v2=3
#_commented=4
notcopied=5'
    assert_rc 0 slkbuild
    assert_contains build-foo.sh "^_srcname=foobar$"
    assert_contains build-foo.sh "^_src_ver=2$"
    assert_contains build-foo.sh "^_v2=3$"
    assert_not_contains build-foo.sh "_commented"
    assert_not_contains build-foo.sh "notcopied"
}

# options=() decides which steps are added to the build script
test_options_steps() {
    write_slkbuild
    assert_rc 0 slkbuild
    for step in extract_source strip_binaries remove_libtool_archives; do
        assert_contains build-foo.sh "^$step$"
    done
    write_slkbuild "options=('noextract' 'nostrip' 'keepla')"
    assert_rc 0 slkbuild
    for step in extract_source strip_binaries remove_libtool_archives; do
        assert_not_contains build-foo.sh "^$step$"
    done
}

test_option_flags_not_taken_from_environment() {
    write_slkbuild
    NOEXTRACT=1 NOSTRIP=1 KEEPLA=1 NOAUTODOTNEW=1 assert_rc 0 slkbuild
    for step in extract_source strip_binaries remove_libtool_archives; do
        assert_contains build-foo.sh "^$step$"
    done
}

test_package_type() {
    write_slkbuild
    assert_rc 0 slkbuild
    assert_contains build-foo.sh '\$package\.txz'
    PKGTYPE=tgz assert_rc 0 slkbuild
    assert_contains build-foo.sh '\$package\.tgz'
    PKGEXT=tbz PKGTYPE=tgz assert_rc 0 slkbuild
    assert_contains build-foo.sh '\$package\.tbz'
    write_slkbuild "options=('tlz')"
    PKGEXT=tbz assert_rc 0 slkbuild
    assert_contains build-foo.sh '\$package\.tlz'
}

test_internal_makepkg_selection() {
    write_slkbuild "options=('makepkginternal')"
    assert_rc 0 slkbuild
    assert_contains build-foo.sh "^makepkg_internal() {"
    write_slkbuild "options=('tbr')"
    assert_rc 0 slkbuild
    assert_contains build-foo.sh "^makepkg_internal() {"
    write_slkbuild
    MAKEPKG=makepkg_internal assert_rc 0 slkbuild
    assert_contains build-foo.sh "^makepkg_internal() {"
}

test_doinst_lookalike_variables_ignored() {
    write_slkbuild 'doinst_msg=hi
douninst_x=hi'
    assert_rc 0 slkbuild
    assert_not_contains build-foo.sh "setup_doinst"
    assert_not_contains build-foo.sh "setup_douninst"
}

test_doinst_variable_substitution() {
    write_slkbuild 'doinst() {
    echo "$pkgname-$pkgver ${pkgname}rc $pkgname.conf"
    echo "lib$LIBDIRSUFFIX/$arch/ $ARCH ${ARCH}x"
    echo "$ARCHIVE $architecture $pkgver_major $pkgnamefile"
}'
    assert_rc 0 slkbuild
    assert_contains build-foo.sh 'echo "foo-1 foorc foo.conf"'
    assert_contains build-foo.sh 'echo "lib64/x86_64/ x86_64 x86_64x"'
    assert_contains build-foo.sh \
        'echo "$ARCHIVE $architecture $pkgver_major $pkgnamefile"'
}

test_packager_lines_copied() {
    for hdr in "#Packager: A <a@b>" "# Packager: A <a@b>" \
               "#Maintainer: A <a@b>" "# Maintainer: A <a@b>"; do
        write_slkbuild
        sed -i "1c$hdr" SLKBUILD
        echo "${hdr%%[PM]*}Former Packager(s): B <b@c>" >> SLKBUILD
        assert_rc 0 slkbuild
        assert_eq "$(sed -n 3p build-foo.sh)" "$hdr" "packager line"
        assert_eq "$(sed -n 4p build-foo.sh)" "${hdr%%[PM]*}Former Packager(s): B <b@c>" \
            "former packager line"
        bash -n build-foo.sh || fail "syntax error"
    done
}

test_arch_flags() {
    write_slkbuild
    while IFS='|' read a flags libdir; do
        arch=$a assert_rc 0 slkbuild
        assert_contains build-foo.sh "^export CFLAGS=\"$flags\"$"
        assert_contains build-foo.sh "^export CXXFLAGS=\"$flags\"$"
        assert_contains build-foo.sh "^export LIBDIRSUFFIX=\"$libdir\"$"
    done <<'EOT'
x86_64|-O2 -fPIC|64
aarch64|-O2 -fPIC|64
i586|-O2 -march=i586 -mtune=i686|
i686|-O2 -march=i686 -mtune=i686|
armv7hl|-O2 -march=armv7-a -mfpu=vfpv3-d16|
arm|-O2 -march=armv5te|
noarch|-O2|
EOT
}

# arch=noarch is usually set in the SLKBUILD itself
test_noarch_in_slkbuild() {
    write_slkbuild 'arch=noarch'
    assert_rc 0 slkbuild
    assert_contains build-foo.sh "^arch=noarch$"
    assert_contains build-foo.sh '^export CFLAGS="-O2"$'
}

# An option line in a template's build() must follow a continued line,
# otherwise the shell runs it as a command of its own
test_templates_option_lines_continued() {
    for template in "$REPO_DIR"/etc/SLKBUILD*; do
        bad=$(awk '/^[ \t]*-/ && prev !~ /\\$/ { print FILENAME ":" FNR ": " $0 }
                   { prev = $0 }' "$template")
        [ -z "$bad" ] || fail "missing line continuation: $bad"
    done
}

test_arch_from_ARCH_environment_variable() {
    write_slkbuild
    unset arch
    ARCH=i586 assert_rc 0 slkbuild
    assert_contains build-foo.sh "^arch=i586$"
    # arch has priority
    arch=i686 ARCH=i586 assert_rc 0 slkbuild
    assert_contains build-foo.sh "^arch=i686$"
}
