source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

cli() {
  omarchy-theme-schedule "$@" 2>&1
}

test_list_marks_a_slot_with_an_invalid_time() {
  write_schedule '{"slots":[{"at":"noon","theme":"a"},{"at":"sunset-30m","theme":"b"}]}'
  assert_eq $'1  (invalid time: noon)\n2  sunset-30m  b' "$(cli list)" "invalid time shown, numbers kept"
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
  add_theme a
  assert_status 1 "zero" omarchy-theme-schedule set 0 07:00 a
  assert_contains "$(cli set 0 07:00 a)" "No slot 0" "set 0 explains"
  assert_status 1 "remove zero" omarchy-theme-schedule remove 0
  assert_contains "$(cli remove 0)" "No slot 0" "remove 0 explains"
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

test_list_shows_every_entry() {
  write_schedule '{"slots":[{"at":"sunrise","theme":"a"},"junk",{"at":"sunset"},{"theme":"b"}]}'
  assert_eq $'1  sunrise  a\n2  (invalid: "junk")\n3  (invalid: {"at":"sunset"})\n4  (invalid: {"theme":"b"})' "$(cli list)" "malformed entries keep their numbers"
}

test_an_empty_config_does_not_swallow_edits() {
  add_theme tokyo-night
  : >"$HOME/.local/state/omarchy/settings/theme-schedule.json"
  assert_status 0 "add" omarchy-theme-schedule add sunset tokyo-night
  assert_eq '[{"at":"sunset","theme":"tokyo-night"}]' "$(read_schedule)" "stored"
  printf '  \n' >"$HOME/.local/state/omarchy/settings/theme-schedule.json"
  assert_status 0 "add over whitespace" omarchy-theme-schedule add sunrise tokyo-night
  assert_eq '[{"at":"sunrise","theme":"tokyo-night"}]' "$(read_schedule)" "stored over whitespace"
}

test_edits_keep_file_permissions() {
  add_theme tokyo-night
  write_schedule '{"slots":[]}'
  chmod 644 "$HOME/.local/state/omarchy/settings/theme-schedule.json"
  omarchy-theme-schedule add sunset tokyo-night
  assert_eq 644 "$(stat -c %a "$HOME/.local/state/omarchy/settings/theme-schedule.json")" "mode kept"
}

test_add_and_remove_apply_at_once_while_on() {
  add_theme flexoki-light tokyo-night
  schedule_on
  set_now "2026-10-28 12:00"
  set_current_theme tokyo-night
  omarchy-theme-schedule add 07:00 flexoki-light
  assert_eq flexoki-light "$(current_theme)" "add applies"
  write_schedule '{"slots":[{"at":"07:00","theme":"flexoki-light"},{"at":"08:00","theme":"tokyo-night"}]}'
  set_current_theme flexoki-light
  omarchy-theme-schedule remove 2
  assert_eq flexoki-light "$(current_theme)" "remove leaves the earlier slot active"
  set_current_theme tokyo-night
  omarchy-theme-schedule remove 1
  assert_eq tokyo-night "$(current_theme)" "no slots, nothing to apply"
  write_schedule '{"slots":[{"at":"07:00","theme":"flexoki-light"},{"at":"08:00","theme":"tokyo-night"}]}'
  set_current_theme flexoki-light
  omarchy-theme-schedule remove 2
  assert_eq flexoki-light "$(current_theme)" "stays"
}

test_set_normalises_and_rejects_themes() {
  add_theme tokyo-night
  write_schedule '{"slots":[{"at":"sunrise","theme":"a"}]}'
  assert_status 0 "set" omarchy-theme-schedule set 1 sunset "Tokyo Night"
  assert_eq '[{"at":"sunset","theme":"tokyo-night"}]' "$(read_schedule)" "normalised"
  assert_status 1 "unknown theme" omarchy-theme-schedule set 1 sunset nope
  assert_contains "$(cli set 1 sunset nope)" "Theme 'nope' is not installed" "explains"
  assert_eq '[{"at":"sunset","theme":"tokyo-night"}]' "$(read_schedule)" "unchanged"
}

test_t_substitutes_each_argument_once() {
  local TS_ENGLISH
  declare -A TS_ENGLISH=([k]="[%1] [%2] [%1]")
  eval "$(sed -n '/^t() {/,/^}/p' "$REPO/bin/omarchy-theme-schedule")"
  assert_eq '[a&b] [c\%1d] [a&b]' "$(t k 'a&b' 'c\%1d')" "arguments are taken literally"
}

run_tests
