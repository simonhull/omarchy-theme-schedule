source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

cli() {
  omarchy-theme-schedule "$@" 2>&1
}

test_list_without_slots() {
  assert_contains "$(cli list)" "No slots" "says there are none"
}

test_add_normalises_and_lists() {
  add_theme tokyo-night flexoki-light
  assert_status 0 "add sunset" omarchy-theme-schedule add sunset "Tokyo Night"
  assert_status 0 "add a clock time" omarchy-theme-schedule add 07:30 flexoki-light
  assert_eq '[{"at":"sunset","theme":"tokyo-night"},{"at":"07:30","theme":"flexoki-light"}]' "$(read_schedule)" "stored"
  assert_eq $'1  sunset  tokyo-night\n2  07:30  flexoki-light' "$(cli list)" "listed in file order"
}

test_add_rejects_a_bad_time() {
  add_theme tokyo-night
  assert_status 1 "fails" omarchy-theme-schedule add noon tokyo-night
  assert_contains "$(cli add noon tokyo-night)" "Not a schedule time: noon" "explains"
  assert_status 1 "nothing written" test -f "$HOME/.local/state/omarchy/settings/theme-schedule.json"
}

test_add_rejects_an_unknown_theme() {
  assert_status 1 "fails" omarchy-theme-schedule add sunset nope
  assert_contains "$(cli add sunset nope)" "Theme 'nope' is not installed" "explains"
}

test_set_replaces_a_slot() {
  add_theme tokyo-night flexoki-light
  write_schedule '{"slots":[{"at":"sunrise","theme":"flexoki-light"},{"at":"sunset","theme":"tokyo-night"}]}'
  assert_status 0 "set" omarchy-theme-schedule set 1 06:45 tokyo-night
  assert_eq '[{"at":"06:45","theme":"tokyo-night"},{"at":"sunset","theme":"tokyo-night"}]' "$(read_schedule)" "replaced"
}

test_remove_a_slot() {
  add_theme tokyo-night flexoki-light
  write_schedule '{"slots":[{"at":"sunrise","theme":"flexoki-light"},{"at":"sunset","theme":"tokyo-night"}]}'
  assert_status 0 "remove" omarchy-theme-schedule remove 1
  assert_eq '[{"at":"sunset","theme":"tokyo-night"}]' "$(read_schedule)" "removed"
}

test_slot_numbers_are_checked() {
  write_schedule '{"slots":[{"at":"sunrise","theme":"a"}]}'
  assert_status 1 "past the end" omarchy-theme-schedule remove 5
  assert_contains "$(cli remove 5)" "No slot 5" "explains"
  assert_status 1 "not a number" omarchy-theme-schedule remove abc
  assert_status 1 "zero" omarchy-theme-schedule set 0 07:00 a
}

test_wrong_arguments_print_usage() {
  assert_status 1 "unknown command" omarchy-theme-schedule frobnicate
  assert_contains "$(cli frobnicate)" "Usage: omarchy-theme-schedule" "usage on stderr"
  assert_status 1 "add needs two arguments" omarchy-theme-schedule add sunset
  assert_status 0 "help" omarchy-theme-schedule --help
}

test_editing_while_off_does_not_switch() {
  add_theme tokyo-night
  omarchy-theme-schedule add sunset tokyo-night
  assert_eq "" "$(stub_log)" "no theme-set, no notification"
}

run_tests
