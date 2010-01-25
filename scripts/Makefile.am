bin_SCRIPTS = slkbuild

do_subst = sed -e 's,[@]version[@],$(PACKAGE_VERSION),g' \
	   -e 's,[@]email[@],$(PACKAGE_BUGREPORT),g' \
	   -e 's,[@]sysconfdir[@],$(sysconfdir),g'

slkbuild: slkbuild.in Makefile
	$(do_subst) < $(srcdir)/slkbuild.in > slkbuild.tmp
	mv slkbuild.tmp slkbuild
