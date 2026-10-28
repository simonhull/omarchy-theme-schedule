# The paths are fixed to /usr: the service's ExecStart and the library default
# in bin/omarchy-theme-schedule both hardcode it. PREFIX is overridable only so
# a DESTDIR-style test install can be laid out; do not install elsewhere.
PREFIX ?= /usr
DESTDIR ?=
NAME = omarchy-theme-schedule
VERSION = $(shell sed -n 's/^pkgver=//p' PKGBUILD)
SHAREDIR = $(DESTDIR)$(PREFIX)/share/$(NAME)
UNITDIR = $(DESTDIR)$(PREFIX)/lib/systemd/user
LICENSEDIR = $(DESTDIR)$(PREFIX)/share/licenses/$(NAME)

.PHONY: test install uninstall dist

test:
	bash test/run.sh

# The source tarball makepkg looks for: with it beside the PKGBUILD, makepkg
# uses it instead of downloading, so `make dist && makepkg -si` builds locally.
# It holds what is committed at HEAD.
dist:
	git archive --prefix=$(NAME)-$(VERSION)/ -o $(NAME)-$(VERSION).tar.gz HEAD

install:
	install -Dm755 bin/$(NAME) $(DESTDIR)$(PREFIX)/bin/$(NAME)
	install -Dm644 lib/theme-schedule/schedule.sh $(SHAREDIR)/schedule.sh
	install -Dm644 lib/theme-schedule/sun.awk $(SHAREDIR)/sun.awk
	install -Dm644 lib/theme-schedule/menu.jsonc $(SHAREDIR)/menu.jsonc
	install -Dm644 systemd/$(NAME).service $(UNITDIR)/$(NAME).service
	install -Dm644 systemd/$(NAME).timer $(UNITDIR)/$(NAME).timer
	install -Dm644 LICENSE $(LICENSEDIR)/LICENSE

# Removes exactly what install puts in place, and the two directories it owns.
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(NAME)
	rm -f $(SHAREDIR)/schedule.sh $(SHAREDIR)/sun.awk $(SHAREDIR)/menu.jsonc
	rm -f $(UNITDIR)/$(NAME).service $(UNITDIR)/$(NAME).timer
	rm -f $(LICENSEDIR)/LICENSE
	rmdir $(SHAREDIR) $(LICENSEDIR)
