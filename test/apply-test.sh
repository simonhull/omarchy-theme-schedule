source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

DAY_NIGHT='{"slots":[{"at":"07:00","theme":"flexoki-light"},{"at":"19:00","theme":"tokyo-night"}]}'

cli() {
  omarchy-theme-schedule "$@" 2>&1
}

given_day_night() {
  add_theme flexoki-light tokyo-night everforest
  write_schedule "$DAY_NIGHT"
  set_current_theme tokyo-night
}

test_apply_does_nothing_while_off() {
  given_day_night
  set_now "2026-10-28 12:00"
  cli apply
  assert_eq "" "$(stub_log)" "no switch"
}

test_apply_switches_to_the_active_slot() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  cli apply
  assert_eq "theme-set flexoki-light" "$(stub_log)" "switched"
  assert_eq "2026-10-28T07:00 07:00->flexoki-light" "$(cat "$HOME/.local/state/omarchy/theme-schedule.applied")" "recorded"
}

test_apply_twice_in_one_slot_switches_once() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  cli apply
  set_now "2026-10-28 12:01"
  cli apply
  assert_eq 1 "$(count_in_log theme-set)" "one switch"
}

test_a_manual_pick_holds_until_the_next_slot() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  cli apply
  set_current_theme everforest
  set_now "2026-10-28 15:00"
  cli apply
  assert_eq everforest "$(current_theme)" "the hand-picked theme stays"
  set_now "2026-10-28 19:00"
  cli apply
  assert_eq tokyo-night "$(current_theme)" "the next slot switches"
}

test_force_reapplies_the_current_slot() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  cli apply
  set_current_theme everforest
  cli apply --force
  assert_eq flexoki-light "$(current_theme)" "forced back"
}

test_apply_records_without_switching_when_already_current() {
  given_day_night
  set_current_theme flexoki-light
  schedule_on
  set_now "2026-10-28 12:00"
  cli apply
  assert_eq 0 "$(count_in_log theme-set)" "no needless switch"
  assert_status 0 "recorded" test -s "$HOME/.local/state/omarchy/theme-schedule.applied"
}

test_a_missing_theme_notifies_once() {
  write_schedule '{"slots":[{"at":"07:00","theme":"gone"}]}'
  schedule_on
  set_now "2026-10-28 12:00"
  cli apply
  cli apply
  assert_eq 1 "$(count_in_log notify)" "one notification"
  assert_contains "$(stub_log)" "Skipped gone" "names the theme"
  assert_eq 0 "$(count_in_log theme-set)" "no switch"
}

test_apply_with_no_slots_is_quiet() {
  schedule_on
  assert_status 0 "exits cleanly" omarchy-theme-schedule apply
  assert_eq "" "$(stub_log)" "does nothing"
}

test_on_seeds_a_dark_current_theme_as_night() {
  add_theme flexoki-light tokyo-night kanagawa
  set_current_theme kanagawa
  set_now "2026-10-28 12:00"
  cli on
  assert_eq '[{"at":"sunrise","theme":"flexoki-light"},{"at":"sunset","theme":"kanagawa"}]' "$(read_schedule)" "seeded"
  assert_status 0 "toggle on" omarchy-toggle-enabled theme-schedule
  assert_contains "$(stub_log)" "systemctl --user enable --now omarchy-theme-schedule.timer" "timer enabled"
  assert_eq flexoki-light "$(current_theme)" "applied at once"
}

test_on_seeds_a_light_current_theme_as_day() {
  add_theme catppuccin-latte tokyo-night
  set_current_theme catppuccin-latte
  export STUB_THEME_MODE=light
  cli on
  assert_eq '[{"at":"sunrise","theme":"catppuccin-latte"},{"at":"sunset","theme":"tokyo-night"}]' "$(read_schedule)" "seeded"
}

test_on_keeps_an_existing_schedule() {
  given_day_night
  cli on
  assert_eq "$(jq -c .slots <<<"$DAY_NIGHT")" "$(read_schedule)" "unchanged"
}

test_off_stops_the_timer() {
  given_day_night
  schedule_on
  cli off
  assert_status 1 "toggle off" omarchy-toggle-enabled theme-schedule
  assert_contains "$(stub_log)" "systemctl --user disable --now omarchy-theme-schedule.timer" "timer disabled"
}

test_editing_while_on_applies_at_once() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  cli set 1 07:00 everforest
  assert_eq everforest "$(current_theme)" "the edited slot applies"
}

test_status_while_off_without_slots() {
  local out
  out=$(cli status)
  assert_contains "$out" "Theme schedule: off" "off"
  assert_contains "$out" "No location set, so sunrise is 07:00 and sunset is 19:00" "fallback explained"
  assert_contains "$out" "No slots" "no slots"
}

test_status_names_a_location_taken_from_the_timezone() {
  export TZ=America/Edmonton
  set_zone_tab $'CA\t+5333-11328\tAmerica/Edmonton\tCST'
  set_now "2026-10-28 12:00"
  assert_contains "$(cli status)" "Location: America/Edmonton (from your timezone)" "timezone location"
}

test_status_shows_today_and_next() {
  local out
  add_theme flexoki-light tokyo-night
  write_schedule '{"slots":[{"at":"sunrise","theme":"flexoki-light"},{"at":"sunset","theme":"tokyo-night"}]}'
  set_location 51.5072 -0.1276 London
  schedule_on
  set_now "2026-12-21 12:00"
  out=$(cli status)
  assert_contains "$out" "Theme schedule: on" "on"
  assert_contains "$out" "Location: London" "location"
  assert_contains "$out" "1  sunrise      08:0" "sunrise row with today's time"
  assert_contains "$out" "flexoki-light  (active)" "active marked"
  assert_contains "$out" "Next switch: tokyo-night at Mon 15:5" "next switch"
}

test_status_is_the_default_command() {
  assert_contains "$(cli)" "Theme schedule: off" "no arguments shows status"
}

test_a_malformed_middle_entry_keeps_slot_numbers() {
  local out
  add_theme flexoki-light tokyo-night
  write_schedule '{"slots":[{"at":"07:00","theme":"flexoki-light"},"junk",{"at":"19:00","theme":"tokyo-night"}]}'
  set_current_theme flexoki-light
  schedule_on
  set_now "2026-10-28 20:00"
  cli apply
  assert_eq "theme-set tokyo-night" "$(stub_log)" "switched to the slot after the junk entry"
  out=$(cli status)
  assert_contains "$out" "  3  19:00 " "slot 3 is listed"
  assert_contains "$out" "tokyo-night  (active)" "slot 3 is active"
  assert_not_contains "$out" "flexoki-light  (active)" "slot 1 is not"
}

test_on_and_off_exit_cleanly_when_notifications_fail() {
  given_day_night
  stub omarchy-notification-send 'exit 1'
  assert_status 0 "on" omarchy-theme-schedule on
  assert_status 0 "off" omarchy-theme-schedule off
}

test_on_reports_a_failed_timer_but_carries_on() {
  given_day_night
  stub systemctl 'exit 1'
  assert_status 1 "on exits 1" omarchy-theme-schedule on
  assert_contains "$(cli on)" "Could not start the schedule timer" "explains"
  assert_status 0 "toggle stays on" omarchy-toggle-enabled theme-schedule
}

test_off_exits_cleanly_when_the_timer_cannot_stop() {
  given_day_night
  schedule_on
  stub systemctl 'exit 1'
  assert_status 0 "off" omarchy-theme-schedule off
}

test_apply_gives_up_quietly_when_another_run_holds_the_lock() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  exec 8>"$XDG_RUNTIME_DIR/omarchy-theme-schedule.lock"
  flock 8
  OMARCHY_THEME_SCHEDULE_LOCK_WAIT=1 omarchy-theme-schedule apply >/dev/null 2>&1
  assert_eq 0 "$?" "exits 0"
  exec 8>&-
  assert_eq "" "$(stub_log)" "no switch"
}

test_force_does_nothing_while_off() {
  given_day_night
  set_now "2026-10-28 12:00"
  cli apply --force
  assert_eq "" "$(stub_log)" "nothing happens"
}

test_on_reapplies_over_a_hand_picked_theme() {
  given_day_night
  set_now "2026-10-28 12:00"
  cli on
  cli apply
  set_current_theme everforest
  cli off
  cli on
  assert_eq flexoki-light "$(current_theme)" "the slot's theme is back"
}

test_concurrent_applies_switch_once() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  stub omarchy-theme-set 'sleep 0.3
echo "theme-set $1" >>"$STUB_LOG"
echo "$1" >"$HOME/.local/state/omarchy/current/theme.name"'
  omarchy-theme-schedule apply &
  omarchy-theme-schedule apply &
  wait
  assert_eq 1 "$(count_in_log theme-set)" "one switch"
}

test_a_failed_switch_is_reported_and_recorded() {
  given_day_night
  schedule_on
  set_now "2026-10-28 12:00"
  stub omarchy-theme-set 'exit 1'
  assert_status 1 "apply fails" omarchy-theme-schedule apply
  assert_contains "$(stub_log)" "Could not switch to flexoki-light" "notified"
  assert_eq "2026-10-28T07:00 07:00->flexoki-light" "$(cat "$HOME/.local/state/omarchy/theme-schedule.applied")" "still recorded"
}

run_tests
