man_MANS = slkbuild.8 SLKBUILD.5
EXTRA_DIST = slkbuild.8.in SLKBUILD.5

do_subst = sed -e 's,[@]email[@],$(PACKAGE_BUGREPORT),g'

slkbuild.8: slkbuild.8.in Makefile
	$(do_subst) < $(srcdir)/slkbuild.8.in > slkbuild.8.tmp
	mv slkbuild.8.tmp slkbuild.8
