#!/bin/bash

# Installs omarchy-theme-schedule as a pacman package and adds
# Appearance › Theme Schedule to the Omarchy menu. Run it as your user:
#
#   curl -fsSL https://raw.githubusercontent.com/simonhull/omarchy-theme-schedule/main/install.sh | bash

set -euo pipefail

REPO="simonhull/omarchy-theme-schedule"
REF="${OMARCHY_THEME_SCHEDULE_REF:-main}"

# Everything happens inside main, called on the last line, so a download cut
# short runs nothing at all.
main() {
  local dir file

  if ((EUID == 0)); then
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

  # Piped through bash, stdin is this script, so nothing may stop to ask a
  # question on it. sudo still asks for the password on the terminal.
  echo "==> Building and installing"
  (cd "$dir" && makepkg --syncdeps --install --nocheck --noconfirm)

  echo "==> Adding Theme Schedule to the Omarchy menu"
  omarchy-theme-schedule setup || echo "The menu was not changed; see the message above."

  cat <<'EOF'

==> Installed. Turn the schedule on from Appearance › Theme Schedule in the
    Omarchy menu, or with:

      omarchy theme schedule on

    It starts with a light theme at sunrise and a dark one at sunset, keeping
    your current theme for whichever half of the day it suits.

      omarchy theme schedule status   # what it will do today
EOF
}

main "$@"
