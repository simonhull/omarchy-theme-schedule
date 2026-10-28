# shellcheck shell=bash
# Test harness for omarchy-theme-schedule. Every test gets a throwaway HOME
# and OMARCHY_PATH, and stubs for each Omarchy command the code calls, so no
# test can change the real desktop. A *-test.sh sources this, defines test_*
# functions, and ends with run_tests.

set -uo pipefail

REAL_HOME=$HOME
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export OMARCHY_THEME_SCHEDULE_LIB="$REPO/lib/theme-schedule"

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf 'FAIL %s: %s\n' "$CURRENT_TEST" "$1"
}

assert_eq() {
  local expected=$1 actual=$2 message=$3
  TESTS_RUN=$((TESTS_RUN + 1))
  [[ $expected == "$actual" ]] || fail "$message"$'\n'"  expected: $expected"$'\n'"  actual:   $actual"
}

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  TESTS_RUN=$((TESTS_RUN + 1))
  [[ -n $needle ]] || { fail "$message"$'\n'"  empty needle"; return; }
  [[ $haystack == *"$needle"* ]] || fail "$message"$'\n'"  missing: $needle"$'\n'"  in: $haystack"
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  TESTS_RUN=$((TESTS_RUN + 1))
  [[ -n $needle ]] || { fail "$message"$'\n'"  empty needle"; return; }
  [[ $haystack != *"$needle"* ]] || fail "$message"$'\n'"  unexpected: $needle"$'\n'"  in: $haystack"
}

# Passes when the command after the message exits with the expected status.
assert_status() {
  local expected=$1 message=$2 actual
  shift 2
  "$@" >/dev/null 2>&1
  actual=$?
  TESTS_RUN=$((TESTS_RUN + 1))
  [[ $actual == "$expected" ]] || fail "$message"$'\n'"  expected status $expected, got $actual"
}

# Passes when two epochs are at most the given number of minutes apart.
assert_within() {
  local actual=$1 expected=$2 minutes=$3 message=$4 diff
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ ! $actual =~ ^[0-9]+$ ]]; then
    fail "$message"$'\n'"  not an epoch: $actual"
    return
  fi
  diff=$((actual - expected))
  diff=${diff#-}
  ((diff <= minutes * 60)) || fail "$message"$'\n'"  off by ${diff}s"
}

stub() {
  printf '#!/bin/bash\n%s\n' "$2" >"$TEST_ROOT/bin/$1"
  chmod +x "$TEST_ROOT/bin/$1"
}

# Answers for the next omarchy-menu-select / omarchy-menu-input calls, in
# order. A call with no answer left behaves like the user dismissing the menu.
answer() {
  printf '%s\n' "$@" >>"$STUB_ANSWERS"
}

stub_log() {
  cat "$STUB_LOG"
}

count_in_log() {
  grep -c -- "$1" "$STUB_LOG"
}

add_theme() {
  local theme
  for theme in "$@"; do
    mkdir -p "$OMARCHY_PATH/themes/$theme"
  done
}

set_current_theme() {
  echo "$1" >"$HOME/.local/state/omarchy/current/theme.name"
}

current_theme() {
  cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null
}

set_location() {
  printf '{"name":"%s","latitude":%s,"longitude":%s}\n' "$3" "$1" "$2" \
    >"$HOME/.local/state/omarchy/settings/weather.json"
}

# Points zone lookups at a tiny zone1970.tab holding the given rows (tab
# separated: countries, coordinates, zone). setup_env's default is empty.
set_zone_tab() {
  printf '%s\n' "$@" >"$TEST_ROOT/zone1970.tab"
  export OMARCHY_THEME_SCHEDULE_ZONE_TAB="$TEST_ROOT/zone1970.tab"
}

set_now() {
  OMARCHY_THEME_SCHEDULE_NOW=$(date -d "$1" +%s)
  export OMARCHY_THEME_SCHEDULE_NOW
}

write_schedule() {
  printf '%s\n' "$1" >"$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

read_schedule() {
  jq -c '.slots' "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

schedule_on() {
  mkdir -p "$HOME/.local/state/omarchy/toggles"
  touch "$HOME/.local/state/omarchy/toggles/theme-schedule"
}

setup_env() {
  local cmd
  TEST_ROOT=$(mktemp -d) || { echo "mktemp failed" >&2; exit 1; }
  export HOME="$TEST_ROOT/home"
  export OMARCHY_PATH="$TEST_ROOT/omarchy"
  export STUB_LOG="$TEST_ROOT/stub.log"
  export STUB_ANSWERS="$TEST_ROOT/answers"
  export TZ=Europe/London
  export LC_ALL=C
  # Cut the test off from the real session: no XDG overrides, bus, or compositor.
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
  mkdir -p "$TEST_ROOT/run"
  export XDG_RUNTIME_DIR="$TEST_ROOT/run"
  unset OMARCHY_THEME_SCHEDULE_NOW STUB_THEME_MODE
  # No timezone has a location unless a test supplies a zone table.
  : >"$TEST_ROOT/empty-zone.tab"
  export OMARCHY_THEME_SCHEDULE_ZONE_TAB="$TEST_ROOT/empty-zone.tab"

  mkdir -p "$HOME/.local/state/omarchy/current" "$HOME/.local/state/omarchy/settings" \
    "$HOME/.config/omarchy/themes" "$OMARCHY_PATH/themes" "$TEST_ROOT/bin"
  : >"$STUB_LOG"
  : >"$STUB_ANSWERS"

  stub omarchy-theme-set 'echo "theme-set $1" >>"$STUB_LOG"
echo "$1" >"$HOME/.local/state/omarchy/current/theme.name"'
  stub omarchy-notification-send 'echo "notify $*" >>"$STUB_LOG"'
  stub systemctl 'echo "systemctl $*" >>"$STUB_LOG"'
  stub omarchy-theme-color 'echo "${STUB_THEME_MODE:-dark}"'
  # The real omarchy-i18n prints the key back when its catalog has no entry,
  # which is the case for every key this package uses.
  stub omarchy-launch-floating-terminal-with-presentation 'echo "float $*" >>"$STUB_LOG"'
  stub omarchy-i18n 'echo "$1"'
  stub omarchy-toggle-enabled '[[ -f $HOME/.local/state/omarchy/toggles/$1 ]]'
  stub omarchy-toggle 'flag="$HOME/.local/state/omarchy/toggles/$1"
case ${2:-toggle} in
  on) mkdir -p "${flag%/*}"; touch "$flag" ;;
  off) rm -f "$flag" ;;
  *) if [[ -f $flag ]]; then rm -f "$flag"; else mkdir -p "${flag%/*}"; touch "$flag"; fi ;;
esac'
  stub omarchy-theme-list 'for dir in "$OMARCHY_PATH"/themes/*/ "$HOME"/.config/omarchy/themes/*/; do
  [[ -d $dir ]] || continue
  basename "$dir"
done | sed -E "s/(^|-)([a-z])/\1\u\2/g; s/-/ /g" | sort -u'
  stub omarchy-menu-select 'prompt=$1
shift
options=()
for arg in "$@"; do
  [[ $arg == -- ]] && break
  options+=("$arg")
done
shift ${#options[@]}
[[ ${1:-} == -- ]] && shift
if (( ${#options[@]} == 0 )) && [[ ! -t 0 ]]; then
  mapfile -t options
fi
{ printf "menu %s:" "$prompt"; printf " [%s]" "${options[@]}"; (( $# )) && printf " args: %s" "$*"; echo; } >>"$STUB_LOG"
answer=$(head -n 1 "$STUB_ANSWERS")
sed -i 1d "$STUB_ANSWERS"
[[ -n $answer ]] || exit 1
printf "%s\n" "$answer"'
  stub omarchy-menu-input 'echo "input $1" >>"$STUB_LOG"
answer=$(head -n 1 "$STUB_ANSWERS")
sed -i 1d "$STUB_ANSWERS"
[[ -n $answer ]] || exit 1
[[ $answer == "<empty>" ]] && answer=""
printf "%s\n" "$answer"'

  # Any real Omarchy or desktop command not stubbed above must fail loudly
  # instead of reaching the real desktop.
  for cmd in /usr/bin/omarchy-* /usr/bin/hyprctl /usr/bin/notify-send /usr/bin/makoctl; do
    [[ -e $cmd && ! -e $TEST_ROOT/bin/${cmd##*/} ]] || continue
    # An installed copy of the command under test must not shadow the repo's.
    [[ ${cmd##*/} == omarchy-theme-schedule ]] && continue
    stub "${cmd##*/}" 'echo "UNSTUBBED ${0##*/} $*" >>"$STUB_LOG"; exit 99'
  done

  export PATH="$TEST_ROOT/bin:$REPO/bin:/usr/bin:/bin"
}

run_tests() {
  local test
  trap 'rm -rf "${TEST_ROOT:-}"' EXIT
  for test in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    CURRENT_TEST=$test
    setup_env
    # Sourced after setup_env so its paths point into this test's HOME.
    if [[ -f $OMARCHY_THEME_SCHEDULE_LIB/schedule.sh ]]; then
      source "$OMARCHY_THEME_SCHEDULE_LIB/schedule.sh"
    fi
    "$test" </dev/null
    rm -rf "$TEST_ROOT"
  done
  printf '%s: %d checks, %d failed\n' "$(basename "$0")" "$TESTS_RUN" "$TESTS_FAILED"
  ((TESTS_FAILED == 0))
}
