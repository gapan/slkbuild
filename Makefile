PREFIX ?= /usr/local
DESTDIR ?= /
ETCDIR ?= etc

nothing:
	@echo "Nothing to make."

install:
	install -Dm 755 src/slkbuild $(DESTDIR)/$(PREFIX)/bin/slkbuild
	install -Dm 644 man/SLKBUILD.5 $(DESTDIR)/$(PREFIX)/man/man5/SLKBUILD.5
	install -Dm 644 man/slkbuild.8 $(DESTDIR)/$(PREFIX)/man/man8/slkbuild.8
	install -d -m 755 $(DESTDIR)/$(ETCDIR)/slkbuild
	install -m 644 etc/SLKBUILD* $(DESTDIR)/$(ETCDIR)/slkbuild/

.PHONY: nothing install
