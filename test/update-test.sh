# shellcheck shell=bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# check-update asks git for the remote's tags; here git is a fake that prints
# a canned tag list (or fails), so nothing touches the network.
CACHE() {
  echo "$HOME/.cache/omarchy-theme-schedule"
}

given_remote_tags() {
  local tag
  : >"$TEST_ROOT/tags"
  for tag in "$@"; do
    printf '%040d\trefs/tags/%s\n' 1 "$tag" >>"$TEST_ROOT/tags"
  done
  stub git 'echo "git $*" >>"$STUB_LOG"
cat "$TEST_ROOT/tags"'
  export TEST_ROOT
}

given_git_fails() {
  stub git 'echo "git $*" >>"$STUB_LOG"
exit 128'
}

# Runs a copy of the CLI that reports 0.1.1, so the tag lists below stay
# "newer" or "older" whatever version the repo is at.
check() {
  sed 's/^TS_VERSION=.*/TS_VERSION=0.1.1/' "$REPO/bin/omarchy-theme-schedule" >"$TEST_ROOT/pinned"
  bash "$TEST_ROOT/pinned" check-update "$@"
}

test_up_to_date_prints_latest() {
  given_remote_tags v0.1.0 v0.1.1
  assert_eq "latest" "$(check)" "output"
  assert_status 0 "exit" check
}

test_newer_remote_prints_available() {
  given_remote_tags v0.1.0 v0.1.1 v0.2.0
  assert_eq "available 0.2.0" "$(check)" "output"
  assert_status 0 "exit" check
}

test_the_highest_tag_wins_by_version_not_by_text() {
  given_remote_tags v0.1.1 v0.10.0 v0.9.0
  assert_eq "available 0.10.0" "$(check)" "version sort"
}

test_older_remote_prints_latest() {
  given_remote_tags v0.0.9
  assert_eq "latest" "$(check)" "output"
}

test_no_tags_prints_nothing() {
  given_remote_tags
  assert_eq "" "$(check)" "output"
  assert_status 0 "exit" check
  assert_status 1 "no cache" test -e "$(CACHE)/latest"
}

test_network_failure_prints_nothing_and_exits_zero() {
  given_git_fails
  assert_eq "" "$(check 2>&1)" "output"
  assert_status 0 "exit" check
  assert_status 0 "exit with --notify" check --notify
  assert_status 1 "no cache" test -e "$(CACHE)/latest"
}

test_failure_keeps_the_last_good_cache() {
  given_remote_tags v0.2.0
  check >/dev/null
  given_git_fails
  check >/dev/null
  assert_eq "0.2.0" "$(cat "$(CACHE)/latest")" "cache kept"
}

test_garbage_tag_list_prints_nothing() {
  given_remote_tags latest v1 v1.2 1.2.3 v1.2.3-rc1 vx.y.z nightly
  assert_eq "" "$(check)" "output"
  assert_status 0 "exit" check
  assert_status 1 "no cache" test -e "$(CACHE)/latest"
}

test_garbage_among_real_tags_is_ignored() {
  given_remote_tags v0.2.0 v9 junk v0.3.0-rc1
  assert_eq "available 0.2.0" "$(check)" "output"
}

test_the_remote_can_be_overridden() {
  given_remote_tags v0.1.1
  OMARCHY_THEME_SCHEDULE_REMOTE=https://example.invalid/repo check >/dev/null
  assert_contains "$(stub_log)" "git ls-remote --tags --refs https://example.invalid/repo" "asks for tags only, at the override"
}

test_default_remote_is_the_github_repo() {
  given_remote_tags v0.1.1
  check >/dev/null
  assert_contains "$(stub_log)" "git ls-remote --tags --refs https://github.com/simonhull/omarchy-theme-schedule" "default url"
}

test_a_hung_remote_is_cut_off() {
  stub git 'sleep 30'
  local start=$SECONDS
  assert_eq "" "$(OMARCHY_THEME_SCHEDULE_CHECK_TIMEOUT=1 check)" "output"
  TESTS_RUN=$((TESTS_RUN + 1))
  ((SECONDS - start < 10)) || fail "took $((SECONDS - start))s"
}

test_the_cache_holds_the_latest_version() {
  given_remote_tags v0.1.1 v0.2.0
  check >/dev/null
  assert_eq "0.2.0" "$(cat "$(CACHE)/latest")" "latest file"
}

test_the_cache_follows_xdg_cache_home() {
  given_remote_tags v0.2.0
  XDG_CACHE_HOME="$TEST_ROOT/xdg" check >/dev/null
  assert_eq "0.2.0" "$(cat "$TEST_ROOT/xdg/omarchy-theme-schedule/latest")" "latest file"
}

test_cached_reads_the_cache_without_the_network() {
  given_remote_tags v0.2.0
  check >/dev/null
  : >"$STUB_LOG"
  assert_eq "available 0.2.0" "$(check --cached)" "available"
  assert_eq 0 "$(count_in_log '^git')" "no git call"
}

test_cached_says_latest_for_a_current_cache() {
  mkdir -p "$(CACHE)"
  echo 0.1.1 >"$(CACHE)/latest"
  assert_eq "latest" "$(check --cached)" "output"
}

test_cached_without_a_cache_prints_nothing() {
  given_remote_tags v0.2.0
  assert_eq "" "$(check --cached)" "output"
  assert_status 0 "exit" check --cached
  assert_eq 0 "$(count_in_log '^git')" "no git call"
}

test_cached_with_a_garbage_cache_prints_nothing() {
  mkdir -p "$(CACHE)"
  echo "not a version" >"$(CACHE)/latest"
  assert_eq "" "$(check --cached)" "output"
  assert_status 0 "exit" check --cached
}

test_cached_never_notifies() {
  mkdir -p "$(CACHE)"
  echo 0.2.0 >"$(CACHE)/latest"
  check --cached --notify >/dev/null
  assert_eq 0 "$(count_in_log '^notify')" "no notification"
}

test_notify_sends_one_notification_for_a_new_version() {
  given_remote_tags v0.2.0
  assert_eq "available 0.2.0" "$(check --notify)" "output"
  assert_eq 1 "$(count_in_log '^notify')" "one notification"
  assert_contains "$(stub_log)" "notify -g 󰸌 Theme Schedule 0.2.0 is available Update it from the Omarchy menu (Update › Theme Schedule) or run: omarchy theme schedule update" "title and body"
}

test_notify_does_not_repeat_for_the_same_version() {
  given_remote_tags v0.2.0
  check --notify >/dev/null
  check --notify >/dev/null
  check --notify >/dev/null
  assert_eq 1 "$(count_in_log '^notify')" "still one"
  assert_eq "0.2.0" "$(cat "$(CACHE)/notified")" "recorded"
}

test_notify_again_for_a_newer_version() {
  given_remote_tags v0.2.0
  check --notify >/dev/null
  given_remote_tags v0.2.0 v0.3.0
  check --notify >/dev/null
  assert_eq 2 "$(count_in_log '^notify')" "two notifications"
  assert_contains "$(stub_log)" "Theme Schedule 0.3.0 is available" "second names the newer version"
  assert_eq "0.3.0" "$(cat "$(CACHE)/notified")" "recorded"
}

test_notify_stays_quiet_when_up_to_date() {
  given_remote_tags v0.1.1
  assert_eq "latest" "$(check --notify)" "output"
  assert_eq 0 "$(count_in_log '^notify')" "no notification"
}

test_check_without_notify_does_not_notify() {
  given_remote_tags v0.2.0
  check >/dev/null
  assert_eq 0 "$(count_in_log '^notify')" "no notification"
  assert_status 1 "nothing recorded" test -e "$(CACHE)/notified"
}

test_a_failing_notification_does_not_fail_the_check() {
  given_remote_tags v0.2.0
  stub omarchy-notification-send 'exit 1'
  assert_status 0 "exit" check --notify
}

test_check_update_is_not_in_the_usage() {
  assert_not_contains "$(omarchy-theme-schedule --help)" "check-update" "hidden"
}

# --- update ---

given_installer() {
  stub curl 'echo "curl $*" >>"$STUB_LOG"
[[ ${FAKE_CURL_FAILS:-} == 1 ]] && exit 22
echo "echo installer-ran >>\"\$STUB_LOG\""'
}

test_update_in_a_terminal_runs_the_installer() {
  given_installer
  OMARCHY_THEME_SCHEDULE_TTY=1 omarchy-theme-schedule update >/dev/null
  assert_contains "$(stub_log)" "curl -fsSL https://raw.githubusercontent.com/simonhull/omarchy-theme-schedule/main/install.sh" "fetches the installer"
  assert_eq 1 "$(count_in_log '^installer-ran')" "ran it"
  assert_eq 0 "$(count_in_log '^float')" "no floating terminal"
}

test_update_installer_url_can_be_overridden() {
  given_installer
  OMARCHY_THEME_SCHEDULE_TTY=1 OMARCHY_THEME_SCHEDULE_INSTALLER_URL=https://example.invalid/install.sh \
    omarchy-theme-schedule update >/dev/null
  assert_contains "$(stub_log)" "curl -fsSL https://example.invalid/install.sh" "override"
}

test_update_without_a_terminal_opens_one() {
  given_installer
  OMARCHY_THEME_SCHEDULE_TTY=0 omarchy-theme-schedule update >/dev/null
  assert_contains "$(stub_log)" "float omarchy-theme-schedule update" "floating terminal runs update"
  assert_eq 0 "$(count_in_log '^curl')" "does not fetch itself"
  assert_eq 0 "$(count_in_log '^installer-ran')" "does not install itself"
}

test_update_detects_stdin_when_not_overridden() {
  given_installer
  # run_tests gives each test /dev/null on stdin: not a terminal.
  omarchy-theme-schedule update >/dev/null
  assert_contains "$(stub_log)" "float omarchy-theme-schedule update" "floating terminal"
}

test_update_reports_a_failed_download() {
  given_installer
  assert_status 1 "fails" env FAKE_CURL_FAILS=1 OMARCHY_THEME_SCHEDULE_TTY=1 omarchy-theme-schedule update
  assert_eq 0 "$(count_in_log '^installer-ran')" "nothing ran"
  assert_contains "$(FAKE_CURL_FAILS=1 OMARCHY_THEME_SCHEDULE_TTY=1 omarchy-theme-schedule update 2>&1)" "Could not download the installer" "explains"
}

test_update_is_in_the_usage_and_args_header() {
  assert_contains "$(omarchy-theme-schedule --help)" "update" "usage"
  assert_contains "$(sed -n 4p "$REPO/bin/omarchy-theme-schedule")" "|update|" "omarchy:args"
}

run_tests
