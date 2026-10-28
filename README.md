# omarchy-theme-schedule

Switch your Omarchy theme on a daily schedule. By default a light theme at
sunrise and a dark one at sunset, using the location the weather panel
already has; add as many slots as you like, at sunrise, sunset, a clock time,
or an offset from either.

Pick a theme by hand and it stays until the next slot.

## Install

    make test
    sudo make install            # or build the PKGBUILD
    omarchy theme schedule setup # adds Appearance › Theme Schedule to the menu
    omarchy theme schedule on

## Use

    omarchy theme schedule status
    omarchy theme schedule add sunset-30m "Tokyo Night"
    omarchy theme schedule add 13:00 everforest
    omarchy theme schedule list
    omarchy theme schedule set 2 sunset kanagawa
    omarchy theme schedule remove 3
    omarchy theme schedule off

`<at>` is `HH:MM`, `sunrise` or `sunset`, with an optional `+`/`-` offset in
minutes or hours: `sunset-30m`, `sunrise+1h`. Without a location, or where the
sun does not rise or set that day, sunrise is 07:00 and sunset 19:00.

## How it works

A systemd user timer runs `omarchy-theme-schedule apply` every minute. It
works out which slot is active and switches with `omarchy-theme-set` only when
that slot changes, so a theme you picked yourself holds until the next one.

| What | Where |
|---|---|
| Schedule | `~/.local/state/omarchy/settings/theme-schedule.json` |
| On/off | `~/.local/state/omarchy/toggles/theme-schedule` |
| Last applied slot | `~/.local/state/omarchy/theme-schedule.applied` |
| Location | `~/.local/state/omarchy/settings/weather.json` (the weather panel's) |
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

    omarchy theme schedule off && omarchy theme schedule teardown
    sudo pacman -R omarchy-theme-schedule

## For Omarchy core

Built to be adopted by moving files: `bin/` into core's `bin/`,
`lib/theme-schedule/` into `default/`, the menu rows into
`default/omarchy/omarchy-menu.jsonc` (then `setup`/`teardown` go), the
`TS_ENGLISH` strings into `default/i18n/en/`, and the units into
`default/systemd/user/`.
