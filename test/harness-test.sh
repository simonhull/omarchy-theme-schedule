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
  assert_eq $'Flexoki Light\nTokyo Night' "$(omarchy-theme-list)" "display names, sorted"
}

test_each_test_gets_its_own_home() {
  assert_contains "$HOME" "$TEST_ROOT" "HOME is under the test root"
}

run_tests
