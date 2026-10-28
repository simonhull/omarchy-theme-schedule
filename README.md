[![test](https://github.com/simonhull/omarchy-theme-schedule/actions/workflows/test.yml/badge.svg)](https://github.com/simonhull/omarchy-theme-schedule/actions/workflows/test.yml)

# omarchy-theme-schedule

Switch your Omarchy theme on a daily schedule. By default a light theme at
sunrise and a dark one at sunset, using the weather panel's location or,
failing that, your timezone's; add as many slots as you like, at sunrise, sunset, a clock time,
or an offset from either.

Pick a theme by hand and it stays until the next slot.

## Install

On Omarchy, as your user:

    curl -fsSL https://raw.githubusercontent.com/simonhull/omarchy-theme-schedule/main/install.sh | bash

That builds and installs it as a pacman package, and adds
Appearance › Theme Schedule to the Omarchy menu. Then turn it on from that
menu, or with:

    omarchy theme schedule on

Running it again upgrades to the latest version, or says so if you already have
it. To rebuild anyway, add `--force`:

    curl -fsSL https://raw.githubusercontent.com/simonhull/omarchy-theme-schedule/main/install.sh | bash -s -- --force

### From a clone

As a package (tracked by pacman):

    make dist && makepkg -si

`make dist` writes `omarchy-theme-schedule-<version>.tar.gz` from the
committed tree, and makepkg uses that local file instead of downloading one.

Or straight into the system (paths are fixed under `/usr`):

    make test
    sudo make install

Then, either way:

    omarchy theme schedule setup # adds Appearance › Theme Schedule to the menu
    omarchy theme schedule on

## Updates

`omarchy update` does not upgrade this package, since it is not in a package
repository. Instead, after each `omarchy update`, a hook checks GitHub for a
newer release and sends one notification per new version. While an update is
waiting, an **Update › Theme Schedule** row appears in the Omarchy menu (and
**Update Theme Schedule** under Appearance › Theme Schedule); either one opens
a terminal and installs it. From a terminal:

    omarchy theme schedule update

The hook and the menu rows are put in place by `omarchy theme schedule setup`
(the installer runs it), so after upgrading from an older version, run `setup`
once. `teardown` removes them.

## Use

    omarchy theme schedule status
    omarchy theme schedule add sunset-30m "Tokyo Night"
    omarchy theme schedule add 13:00 everforest
    omarchy theme schedule list
    omarchy theme schedule set 2 sunset kanagawa
    omarchy theme schedule remove 3
    omarchy theme schedule off

`<at>` is `HH:MM`, `sunrise` or `sunset`, with an optional `+`/`-` offset in
minutes or hours: `sunset-30m`, `sunrise+1h`.

Sunrise and sunset use the weather panel's location if one is set (from the
panel, or with `omarchy weather location`). Most installs have none, because
the panel detects its location in memory, so the coordinates of your timezone
are used next (from `/usr/share/zoneinfo/zone1970.tab`: a city in your zone,
good to a few minutes). With neither, or where the sun does not rise or set
that day, sunrise is 07:00 and sunset 19:00. `status` says which applies.

## How it works

A systemd user timer runs `omarchy-theme-schedule apply` every minute. It
works out which slot is active and switches with `omarchy-theme-set` only when
that slot changes, so a theme you picked yourself holds until the next one.

| What | Where |
|---|---|
| Schedule | `~/.local/state/omarchy/settings/theme-schedule.json` |
| On/off | `~/.local/state/omarchy/toggles/theme-schedule` |
| Last applied slot | `~/.local/state/omarchy/theme-schedule.applied` |
| Location | `~/.local/state/omarchy/settings/weather.json` (the weather panel's), else your timezone's |
| Update hook | `~/.config/omarchy/hooks/post-update.d/omarchy-theme-schedule` |
| Latest release seen, and last one notified | `~/.cache/omarchy-theme-schedule/latest` and `notified` |
| Menu rows | between `// theme-schedule:begin` and `:end` in `~/.config/omarchy/extensions/omarchy-menu.jsonc` |

### Menu file notes

`setup` and `teardown` edit only the marked block, and leave the file
unchanged (with a message) when it cannot do so safely:

- the markers are damaged: only one of begin/end, or two blocks;
- the file wraps its rows in `"items"`: add the rows inside it by hand;
- the file has no line holding only `{`, so there is nowhere to insert.

If the menu file is a symlink (as a dotfiles manager makes it), the target is
edited and the link is kept.

## Uninstall

First, as your user:

    omarchy theme schedule off && omarchy theme schedule teardown

Then remove the files the way you installed them:

    sudo pacman -R omarchy-theme-schedule   # after makepkg -si
    sudo make uninstall                     # after sudo make install

## For Omarchy core

Adopting this is more than moving files:

- `bin/` goes into core's `bin/`, and the units into `default/systemd/user/`
  (keep `KillMode=process` and the timeout).
- The library moves to `$OMARCHY_PATH/default/theme-schedule`; the default for
  `TS_LIB` becomes that path.
- The `TS_ENGLISH` table becomes `default/i18n/en/cli.json` entries, and the
  menu labels become `menu.json` entries.
- `t()` collapses to a call to `omarchy-i18n`.
- The menu rows go into `default/omarchy/omarchy-menu.jsonc`, and `setup`,
  `teardown` and the menu-block helpers are deleted.
- The tests would need porting to core's test conventions.
