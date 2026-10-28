source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

test_theme_set_stub_records_and_switches() {
  omarchy-theme-set tokyo-night
  assert_eq "theme-set tokyo-night" "$(stub_log)" "theme-set is logged"
  assert_eq "tokyo-night" "$(current_theme)" "theme-set changes the current theme"
}

test_toggle_stub_turns_flag_on_and_off() {
  assert_status 1 "off by default" omarchy-toggle-enabled theme-schedule
  omarchy-toggle theme-schedule on
  assert_status 0 "on after on" omarchy-toggle-enabled theme-schedule
  omarchy-toggle theme-schedule off
  assert_status 1 "off after off" omarchy-toggle-enabled theme-schedule
}

test_menu_select_stub_pops_answers_in_order() {
  answer "first" "second"
  assert_eq "first" "$(omarchy-menu-select Pick a b)" "first answer"
  assert_eq "second" "$(omarchy-menu-select Pick a b)" "second answer"
  assert_status 1 "no answer left means dismissed" omarchy-menu-select Pick a b
  assert_contains "$(stub_log)" "menu Pick: [a] [b]" "options are logged"
}

test_theme_list_stub_prints_display_names() {
  add_theme tokyo-night flexoki-light
  mkdir -p "$HOME/.config/omarchy/themes/my-custom" "$HOME/.config/omarchy/themes/tokyo-night"
  assert_eq $'Flexoki Light\nMy Custom\nTokyo Night' "$(omarchy-theme-list)" "display names, user themes included, de-duplicated, sorted"
}

test_each_test_gets_its_own_home() {
  assert_status 0 "TEST_ROOT is set" test -n "$TEST_ROOT"
  assert_eq "$TEST_ROOT/home" "$HOME" "HOME is inside the test root"
  assert_status 1 "HOME is not the real home" test "$HOME" = "$REAL_HOME"
}

# Tests run alphabetically, so a_ records its root and b_ compares against it.
test_roots_a_records_root() {
  PREVIOUS_ROOT=$TEST_ROOT
}

test_roots_b_differs_from_previous() {
  assert_status 0 "previous root was recorded" test -n "${PREVIOUS_ROOT:-}"
  assert_status 1 "each test gets a fresh root" test "$TEST_ROOT" = "${PREVIOUS_ROOT:-}"
  assert_status 1 "previous root is removed" test -e "${PREVIOUS_ROOT:-/nonexistent-}"
}

test_stubs_come_first_on_path() {
  assert_eq "$TEST_ROOT/bin/omarchy-theme-set" "$(command -v omarchy-theme-set)" "stub shadows the real command"
}

test_unstubbed_omarchy_commands_fail_loudly() {
  [[ -e /usr/bin/omarchy-theme-current ]] || return 0
  omarchy-theme-current >/dev/null 2>&1
  assert_eq 99 "$?" "unstubbed command exits 99"
  assert_contains "$(stub_log)" "UNSTUBBED omarchy-theme-current" "unstubbed call is logged"
}

run_tests
