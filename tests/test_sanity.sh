# Sanity checks done on the SLKBUILD before generating the build script
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

test_valid_slkbuild() {
    write_slkbuild
    assert_rc 0 slkbuild
}

test_required_variables() {
    for var in pkgname pkgver pkgrel slackdesc; do
        write_slkbuild
        sed -i "/^$var=/d" SLKBUILD
        assert_rc 1 slkbuild
        assert_contains slkbuild.out "variable \"$var\" is not set"
    done
}

test_missing_build() {
    write_slkbuild
    sed -i '/^build() {/,$d' SLKBUILD
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "No build() function found"
}

# A variable whose name starts with "build" is not a build() function
test_build_lookalike_variable() {
    write_slkbuild 'buildopts="--foo"'
    sed -i '/^build() {/,$d' SLKBUILD
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "No build() function found"
}

test_build_function_keyword_syntax() {
    write_slkbuild
    sed -i 's/^build() {/function build {/' SLKBUILD
    assert_rc 0 slkbuild
}

test_dash_in_pkgver() {
    write_slkbuild
    sed -i 's/^pkgver=.*/pkgver=1-2/' SLKBUILD
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "No dashes allowed in pkgver"
}

test_slackdesc_too_many_lines() {
    write_slkbuild 'slackdesc=(1 2 3 4 5 6 7 8 9 10 11)'
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "No more than 10 lines"
}

test_slackdesc_line_too_long() {
    long=$(printf 'x%.0s' $(seq 71))
    write_slkbuild "slackdesc=(\"foo (test)\" \"$long\")"
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "Line 2: .* is greater than 70 characters"
    write_slkbuild "slackdesc=(\"foo (test)\" \"${long:1}\")"
    assert_rc 0 slkbuild
}

test_packager_line_accepted_forms() {
    for hdr in "#Packager: A <a@b>" "# Packager: A <a@b>" \
               "#Maintainer: A <a@b>" "# Maintainer: A <a@b>"; do
        write_slkbuild
        sed -i "1c$hdr" SLKBUILD
        assert_rc 0 slkbuild
    done
}

test_packager_line_missing() {
    for hdr in "#Author: A <a@b>" "# just a comment"; do
        write_slkbuild
        sed -i "1c$hdr" SLKBUILD
        assert_rc 1 slkbuild
        assert_contains slkbuild.out "Please specify #Packager: or #Maintainer:"
    done
}

test_packager_line_placeholder() {
    write_slkbuild
    sed -i '1c#Packager: Name <email@address.com>' SLKBUILD
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "Packager or Maintainer isn't set"
}

test_invalid_option_in_options() {
    write_slkbuild "options=('nosuchoption')"
    assert_rc 2 slkbuild
    assert_contains slkbuild.out "nosuchoption is not a correct option"
}

test_missing_local_source() {
    write_slkbuild 'source=("missing.patch")'
    assert_rc 1 slkbuild
    assert_contains slkbuild.out "does not appear to be a url"
}

test_commented_variables_warning() {
    write_slkbuild '#url=
#CFLAGS='
    assert_rc 0 slkbuild
    assert_contains slkbuild.out "WARNING: You appear to have too many commented variables"
    assert_contains slkbuild.out "edit the SLKBUILD templates in $REPO_DIR/etc"
    write_slkbuild '#url='
    assert_rc 0 slkbuild
    assert_not_contains slkbuild.out "commented variables"
}
