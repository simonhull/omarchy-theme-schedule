# shellcheck shell=bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# install.sh runs against stubs: curl copies fixtures, makepkg fakes the
# pacman version change by writing a file, and pacman -Q reads it.
given_fixtures() {
  local version=$1 release=${2:-1}
  mkdir -p "$TEST_ROOT/fixtures"
  printf 'pkgver=%s\npkgrel=%s\n' "$version" "$release" >"$TEST_ROOT/fixtures/PKGBUILD"
  : >"$TEST_ROOT/fixtures/omarchy-theme-schedule.install"
  export INSTALLED_FILE="$TEST_ROOT/installed" FIXTURES="$TEST_ROOT/fixtures"
  export OMARCHY_THEME_SCHEDULE_EUID=1000
  stub curl 'while (($#)); do
  case $1 in
    -o) out=$2; shift ;;
    http*) url=$1 ;;
  esac
  shift
done
echo "curl $url" >>"$STUB_LOG"
cp "$FIXTURES/${url##*/}" "$out"'
  stub makepkg 'echo "makepkg $*" >>"$STUB_LOG"
[[ -f PKGBUILD ]] || exit 1
echo "$(sed -n "s/^pkgver=//p" PKGBUILD)-$(sed -n "s/^pkgrel=//p" PKGBUILD)" >"$INSTALLED_FILE"'
  stub pacman '[[ $1 == -Q && $2 == omarchy-theme-schedule && -f $INSTALLED_FILE ]] || exit 1
echo "omarchy-theme-schedule $(cat "$INSTALLED_FILE")"'
  stub omarchy-theme-schedule 'echo "schedule $*" >>"$STUB_LOG"'
}

given_installed() {
  echo "$1" >"$INSTALLED_FILE"
}

install_it() {
  bash "$REPO/install.sh" "$@" 2>&1
}

test_fresh_install() {
  given_fixtures 0.1.1
  local out
  out=$(install_it)
  assert_contains "$out" "Installed 0.1.1" "says installed"
  assert_not_contains "$out" "Upgraded" "not an upgrade"
  assert_eq 1 "$(count_in_log '^makepkg --syncdeps --install')" "built once"
  assert_contains "$(stub_log)" "schedule setup" "menu set up"
}

test_upgrade() {
  given_fixtures 0.1.1
  given_installed 0.1.0-1
  assert_contains "$(install_it)" "Upgraded 0.1.0 → 0.1.1" "says upgraded"
  assert_eq 1 "$(count_in_log '^makepkg')" "built once"
}

test_same_version_skips_the_build() {
  given_fixtures 0.1.1
  given_installed 0.1.1-1
  local out
  out=$(install_it)
  assert_contains "$out" "omarchy-theme-schedule 0.1.1 is already installed" "says so"
  assert_eq 0 "$(count_in_log '^makepkg')" "no build"
  assert_eq 0 "$(count_in_log 'schedule setup')" "no menu change"
}

test_a_newer_release_of_the_same_version_builds() {
  given_fixtures 0.1.1 2
  given_installed 0.1.1-1
  install_it >/dev/null
  assert_eq 1 "$(count_in_log '^makepkg')" "pkgrel counts"
}

test_force_rebuilds_the_same_version() {
  given_fixtures 0.1.1
  given_installed 0.1.1-1
  assert_contains "$(install_it --force)" "Reinstalled 0.1.1" "says reinstalled"
  assert_eq 1 "$(count_in_log '^makepkg')" "built"
}

test_force_through_a_pipe() {
  given_fixtures 0.1.1
  given_installed 0.1.1-1
  bash -s -- --force <"$REPO/install.sh" >/dev/null 2>&1
  assert_eq 1 "$(count_in_log '^makepkg')" "bash -s -- --force builds"
}

test_force_from_the_environment() {
  given_fixtures 0.1.1
  given_installed 0.1.1-1
  OMARCHY_THEME_SCHEDULE_FORCE=1 install_it >/dev/null
  assert_eq 1 "$(count_in_log '^makepkg')" "env var builds"
}

test_unknown_option_is_refused() {
  given_fixtures 0.1.1
  assert_status 2 "unknown option" bash "$REPO/install.sh" --frobnicate
  assert_eq 0 "$(count_in_log '^makepkg')" "no build"
}

test_closing_message_when_the_schedule_is_off() {
  given_fixtures 0.1.1
  local out
  out=$(install_it)
  assert_contains "$out" "omarchy theme schedule on" "tells how to turn it on"
}

test_closing_message_when_the_schedule_is_on() {
  given_fixtures 0.1.1
  given_installed 0.1.0-1
  schedule_on
  local out
  out=$(install_it)
  assert_not_contains "$out" "omarchy theme schedule on" "does not offer to turn it on"
  assert_contains "$out" "unchanged" "says it is unchanged"
  assert_contains "$out" "omarchy theme schedule status" "points at status"
}

test_refuses_to_run_as_root() {
  given_fixtures 0.1.1
  export OMARCHY_THEME_SCHEDULE_EUID=0
  assert_status 1 "root" bash "$REPO/install.sh"
  assert_contains "$(install_it)" "not root" "explains"
  assert_eq 0 "$(count_in_log '^curl')" "fetched nothing"
}

test_needs_omarchy() {
  given_fixtures 0.1.1
  # An empty PATH: the real omarchy-theme-set on this machine must not count.
  mkdir "$TEST_ROOT/empty"
  assert_status 1 "no omarchy" env PATH="$TEST_ROOT/empty" /usr/bin/bash "$REPO/install.sh"
  assert_contains "$(env PATH="$TEST_ROOT/empty" /usr/bin/bash "$REPO/install.sh" 2>&1)" "needs Omarchy" "explains"
  assert_eq 0 "$(count_in_log '^makepkg')" "no build"
}

test_a_successful_install_exits_zero() {
  given_fixtures 0.1.1
  assert_status 0 "exit status" bash "$REPO/install.sh"
  assert_eq "" "$(install_it | grep -i 'unbound')" "no trap error"
}

test_install_refreshes_the_update_check() {
  given_fixtures 0.1.1
  given_installed 0.1.0-1
  install_it >/dev/null
  assert_eq 1 "$(count_in_log '^schedule check-update$')" "checks once"
  # After setup, so it is the new version that checks.
  assert_eq "schedule setup
schedule check-update" "$(grep '^schedule' "$STUB_LOG")" "order"
}

test_a_failing_update_check_does_not_fail_the_install() {
  given_fixtures 0.1.1
  stub omarchy-theme-schedule 'echo "schedule $*" >>"$STUB_LOG"
[[ $1 == check-update ]] && exit 1
exit 0'
  assert_contains "$(install_it)" "Installed 0.1.1" "finishes"
  rm -f "$INSTALLED_FILE"
  assert_status 0 "install still succeeds" bash "$REPO/install.sh"
}

test_same_version_skips_the_update_check() {
  given_fixtures 0.1.1
  given_installed 0.1.1-1
  install_it >/dev/null
  assert_eq 0 "$(count_in_log 'check-update')" "nothing changed"
}

run_tests
