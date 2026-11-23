PREFIX ?= /usr/local
DESTDIR ?= /
SYSCONFDIR ?= /etc

all: slkbuild man

# Always regenerated, so that a different SYSCONFDIR is never ignored
slkbuild:
	sed "s|@sysconfdir@|$(SYSCONFDIR)|g" src/slkbuild > slkbuild
	chmod 755 slkbuild

install: all
	install -Dm 755 slkbuild $(DESTDIR)/$(PREFIX)/bin/slkbuild
	install -Dm 644 man/SLKBUILD.5 $(DESTDIR)/$(PREFIX)/man/man5/SLKBUILD.5
	install -Dm 644 man/slkbuild.8 $(DESTDIR)/$(PREFIX)/man/man8/slkbuild.8
	install -d -m 755 $(DESTDIR)/$(SYSCONFDIR)/slkbuild
	install -m 644 etc/SLKBUILD* $(DESTDIR)/$(SYSCONFDIR)/slkbuild/

man:
	make man -C man

clean:
	rm -f slkbuild
	make clean -C man

test:
	tests/run.sh

.PHONY: all slkbuild install man clean test
