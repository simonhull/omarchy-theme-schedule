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
DISPATCHDIR = $(DESTDIR)$(PREFIX)/share/omarchy/bin

.PHONY: test install uninstall dist release

test:
	bash test/run.sh

# The source tarball makepkg looks for: with it beside the PKGBUILD, makepkg
# uses it instead of downloading, so `make dist && makepkg -si` builds locally.
# It holds what is committed at HEAD.
dist:
	git archive --prefix=$(NAME)-$(VERSION)/ -o $(NAME)-$(VERSION).tar.gz HEAD

# make release VERSION=x.y.z; see tools/release.sh for what it does and in what order.
release:
	@test "$(origin VERSION)" = "command line" || { echo "usage: make release VERSION=x.y.z" >&2; exit 1; }
	bash tools/release.sh $(VERSION)

install:
	install -Dm755 bin/$(NAME) $(DESTDIR)$(PREFIX)/bin/$(NAME)
	install -Dm644 lib/theme-schedule/schedule.sh $(SHAREDIR)/schedule.sh
	install -Dm644 lib/theme-schedule/sun.awk $(SHAREDIR)/sun.awk
	install -Dm644 lib/theme-schedule/menu.jsonc $(SHAREDIR)/menu.jsonc
	install -Dm644 lib/theme-schedule/post-update.hook $(SHAREDIR)/post-update.hook
	install -Dm644 systemd/$(NAME).service $(UNITDIR)/$(NAME).service
	install -Dm644 systemd/$(NAME).timer $(UNITDIR)/$(NAME).timer
	install -Dm644 LICENSE $(LICENSEDIR)/LICENSE
	# `omarchy <group> <name>` only routes commands linked into Omarchy's own
	# bin directory, the way core links each of its commands there.
	install -d $(DISPATCHDIR)
	ln -sf $(PREFIX)/bin/$(NAME) $(DISPATCHDIR)/$(NAME)

# Removes exactly what install puts in place, and the two directories it owns.
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(NAME)
	rm -f $(SHAREDIR)/schedule.sh $(SHAREDIR)/sun.awk $(SHAREDIR)/menu.jsonc $(SHAREDIR)/post-update.hook
	rm -f $(UNITDIR)/$(NAME).service $(UNITDIR)/$(NAME).timer
	rm -f $(LICENSEDIR)/LICENSE
	rm -f $(DISPATCHDIR)/$(NAME)
	rmdir $(SHAREDIR) $(LICENSEDIR)
