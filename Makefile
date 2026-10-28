PREFIX ?= /usr
DESTDIR ?=
NAME = omarchy-theme-schedule
SHAREDIR = $(DESTDIR)$(PREFIX)/share/$(NAME)

.PHONY: test install

test:
	bash test/run.sh

install:
	install -Dm755 bin/$(NAME) $(DESTDIR)$(PREFIX)/bin/$(NAME)
	install -Dm644 lib/theme-schedule/schedule.sh $(SHAREDIR)/schedule.sh
	install -Dm644 lib/theme-schedule/sun.awk $(SHAREDIR)/sun.awk
	install -Dm644 lib/theme-schedule/menu.jsonc $(SHAREDIR)/menu.jsonc
	install -Dm644 systemd/$(NAME).service $(DESTDIR)$(PREFIX)/lib/systemd/user/$(NAME).service
	install -Dm644 systemd/$(NAME).timer $(DESTDIR)$(PREFIX)/lib/systemd/user/$(NAME).timer
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/$(NAME)/LICENSE
