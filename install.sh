#!/bin/bash

# Installs omarchy-theme-schedule as a pacman package and adds
# Appearance › Theme Schedule to the Omarchy menu. Run it as your user:
#
#   curl -fsSL https://raw.githubusercontent.com/simonhull/omarchy-theme-schedule/main/install.sh | bash
#
# It does nothing when the latest version is already installed. To rebuild
# anyway, pass --force; piped through bash the argument goes after "-s --":
#
#   curl -fsSL https://raw.githubusercontent.com/simonhull/omarchy-theme-schedule/main/install.sh | bash -s -- --force
#
# or set OMARCHY_THEME_SCHEDULE_FORCE=1.

set -euo pipefail

REPO="simonhull/omarchy-theme-schedule"
REF="${OMARCHY_THEME_SCHEDULE_REF:-main}"
PACKAGE="omarchy-theme-schedule"

# The version pacman has installed ("0.1.1-1"), or nothing if it has none.
installed_version() {
  pacman -Q "$PACKAGE" 2>/dev/null | awk '{ print $2 }' || true
}

# "0.1.1-1" shown as "0.1.1": a first release of a version is the usual case.
shown() {
  echo "${1%-1}"
}

# Everything happens inside main, called on the last line, so a download cut
# short runs nothing at all.
main() {
  local dir file force=false before after pkgver pkgrel

  [[ ${OMARCHY_THEME_SCHEDULE_FORCE:-} == 1 ]] && force=true
  for file in "$@"; do
    case $file in
      --force) force=true ;;
      *)
        echo "Unknown option: $file (the only one is --force)" >&2
        exit 2
        ;;
    esac
  done

  # OMARCHY_THEME_SCHEDULE_EUID exists so a test can pretend to be root.
  if (("${OMARCHY_THEME_SCHEDULE_EUID:-$EUID}" == 0)); then
    echo "Run this as your user, not root; it asks for sudo when it needs it." >&2
    exit 1
  fi

  if ! command -v omarchy-theme-set >/dev/null; then
    echo "omarchy-theme-schedule needs Omarchy: https://omarchy.org" >&2
    exit 1
  fi

  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT

  echo "==> Fetching the package build"
  for file in PKGBUILD omarchy-theme-schedule.install; do
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/$file" -o "$dir/$file"
  done

  pkgver=$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD")
  pkgrel=$(sed -n 's/^pkgrel=//p' "$dir/PKGBUILD")
  if [[ -z $pkgver || -z $pkgrel ]]; then
    echo "The fetched PKGBUILD has no pkgver or pkgrel." >&2
    exit 1
  fi

  before=$(installed_version)
  if [[ $before == "$pkgver-$pkgrel" && $force == false ]]; then
    echo "$PACKAGE $(shown "$before") is already installed. Pass --force to rebuild it."
    exit 0
  fi

  # Piped through bash, stdin is this script, so nothing may stop to ask a
  # question on it. sudo still asks for the password on the terminal.
  echo "==> Building and installing"
  (cd "$dir" && makepkg --syncdeps --install --nocheck --noconfirm)

  after=$(installed_version)
  if [[ -z $before ]]; then
    echo "==> Installed $(shown "$after")"
  elif [[ $before == "$after" ]]; then
    echo "==> Reinstalled $(shown "$after")"
  else
    echo "==> Upgraded $(shown "$before") → $(shown "$after")"
  fi

  echo "==> Adding Theme Schedule to the Omarchy menu"
  omarchy-theme-schedule setup || echo "The menu was not changed; see the message above."

  if omarchy-toggle-enabled theme-schedule; then
    cat <<'EOT'

==> The schedule is on and unchanged. What it will do today:

      omarchy theme schedule status
EOT
  else
    cat <<'EOT'

==> The schedule is off. Turn it on from Appearance › Theme Schedule in the
    Omarchy menu, or with:

      omarchy theme schedule on

    It starts with a light theme at sunrise and a dark one at sunset, keeping
    your current theme for whichever half of the day it suits.

      omarchy theme schedule status   # what it will do today
EOT
  fi
}

main "$@"
