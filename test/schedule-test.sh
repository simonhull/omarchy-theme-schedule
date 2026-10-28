source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

epoch() {
  date -d "$1" +%s
}

test_parse_at_accepts_times_and_sun_events() {
  assert_eq "07:30 0" "$(ts_parse_at 07:30)" "clock time"
  assert_eq "sunrise 0" "$(ts_parse_at sunrise)" "sunrise"
  assert_eq "sunset -1800" "$(ts_parse_at sunset-30m)" "minutes before"
  assert_eq "sunrise 3600" "$(ts_parse_at sunrise+1h)" "hours after"
  assert_eq "23:59 5400" "$(ts_parse_at 23:59+90m)" "offset on a clock time"
}

test_parse_at_rejects_everything_else() {
  local bad
  for bad in 24:00 7:30 noon sunset-30 sunset+-1h Sunset "" "07:30 "; do
    assert_status 1 "rejects '$bad'" ts_parse_at "$bad"
  done
}

test_normalize_theme_matches_omarchy_theme_set() {
  assert_eq tokyo-night "$(ts_normalize_theme "Tokyo Night")" "spaces and case"
  assert_eq flexoki-light "$(ts_normalize_theme "<b>Flexoki Light</b>")" "markup stripped"
}

test_theme_installed_checks_both_theme_dirs() {
  add_theme tokyo-night
  mkdir -p "$HOME/.config/omarchy/themes/mine"
  assert_status 0 "official theme" ts_theme_installed tokyo-night
  assert_status 0 "user theme" ts_theme_installed mine
  assert_status 1 "missing theme" ts_theme_installed gone
  assert_status 1 "no path escapes" ts_theme_installed ../themes
  assert_status 1 "no empty name" ts_theme_installed ""
}

test_clock_epoch_is_local_time() {
  assert_eq "$(epoch "2026-10-28 07:30")" "$(ts_clock_epoch 2026-10-28 07:30)" "plain day"
}

test_clock_epoch_in_a_dst_gap_counts_from_midnight() {
  # 01:30 does not exist in London on 2026-03-29; 90 minutes after midnight is 02:30 BST.
  assert_eq "$(epoch "2026-03-29 02:30")" "$(ts_clock_epoch 2026-03-29 01:30)" "spring-forward gap"
}

test_sun_event_uses_the_weather_location() {
  set_location 51.5072 -0.1276 London
  assert_within "$(ts_sun_event 2026-06-21 sunrise)" "$(date -u -d "2026-06-21 03:43:04 UTC" +%s)" 2 "London sunrise"
  assert_eq "" "$(ts_sun_fallback 2026-06-21)" "no fallback with a location"
}

test_sun_event_without_location_falls_back() {
  assert_eq "$(epoch "2026-06-21 07:00")" "$(ts_sun_event 2026-06-21 sunrise)" "fallback sunrise"
  assert_eq "$(epoch "2026-06-21 19:00")" "$(ts_sun_event 2026-06-21 sunset)" "fallback sunset"
  assert_eq no-location "$(ts_sun_fallback 2026-06-21)" "reason"
}

test_sun_event_with_null_coordinates_falls_back() {
  printf '{"name":"","latitude":null,"longitude":null}\n' >"$HOME/.local/state/omarchy/settings/weather.json"
  assert_eq no-location "$(ts_sun_fallback 2026-06-21)" "null coordinates are no location"
}

test_sun_event_on_a_polar_day_falls_back() {
  export TZ=Europe/Oslo
  set_location 69.6492 18.9553 Tromsø
  assert_eq "$(epoch "2026-06-21 19:00")" "$(ts_sun_event 2026-06-21 sunset)" "fallback sunset"
  assert_eq polar "$(ts_sun_fallback 2026-06-21)" "reason"
}

test_resolve_slot_applies_offsets() {
  set_location 51.5072 -0.1276 London
  assert_within "$(ts_resolve_slot 2026-12-21 sunset-30m)" "$(( $(date -u -d "2026-12-21 15:53:31 UTC" +%s) - 1800 ))" 2 "sunset-30m"
  assert_eq "$(epoch "2026-10-29 00:30")" "$(ts_resolve_slot 2026-10-28 23:30+1h)" "offset past midnight"
}

test_resolve_slot_rejects_bad_times() {
  assert_status 1 "bad at" ts_resolve_slot 2026-10-28 noon
}


DAY_NIGHT='{"slots":[{"at":"07:00","theme":"day"},{"at":"19:00","theme":"night"}]}'

active_theme() {
  ts_active "$(ts_now)" | cut -f4
}

test_active_between_slots() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-28 12:00"
  assert_eq day "$(active_theme)" "midday is the day slot"
}

test_active_at_a_slot_boundary() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-28 19:00"
  assert_eq night "$(active_theme)" "a slot is active from its own minute"
}

test_active_before_first_slot_wraps_to_yesterday() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-28 03:00"
  assert_eq night "$(active_theme)" "early morning is last night's slot"
  assert_eq "2026-10-27T19:00 19:00->night" "$(ts_occurrence_key "$(ts_active "$(ts_now)")")" "yesterday's occurrence"
}

test_file_order_does_not_matter() {
  write_schedule '{"slots":[{"at":"19:00","theme":"night"},{"at":"07:00","theme":"day"}]}'
  set_now "2026-10-28 12:00"
  assert_eq day "$(active_theme)" "slots are ordered by time"
}

test_three_or_more_slots_and_ties() {
  write_schedule '{"slots":[{"at":"07:00","theme":"a"},{"at":"13:00","theme":"b"},{"at":"13:00","theme":"c"},{"at":"21:00","theme":"d"}]}'
  set_now "2026-10-28 10:00"
  assert_eq a "$(active_theme)" "morning"
  set_now "2026-10-28 14:00"
  assert_eq c "$(active_theme)" "of two slots on one minute, the later in the file wins"
  set_now "2026-10-28 22:00"
  assert_eq d "$(active_theme)" "night"
}

test_offset_that_crosses_midnight() {
  write_schedule '{"slots":[{"at":"12:00","theme":"noon"},{"at":"23:30+1h","theme":"late"}]}'
  set_now "2026-10-28 00:15"
  assert_eq noon "$(active_theme)" "before yesterday's 23:30+1h lands"
  set_now "2026-10-28 00:45"
  assert_eq late "$(active_theme)" "after it lands"
}

test_dst_start_in_new_york() {
  export TZ=America/New_York
  write_schedule "$DAY_NIGHT"
  set_now "2026-03-08 06:59"
  assert_eq night "$(active_theme)" "just before 07:00 EDT"
  set_now "2026-03-08 07:00"
  assert_eq day "$(active_theme)" "07:00 EDT"
}

test_dst_end_in_london() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-25 06:59"
  assert_eq night "$(active_theme)" "just before 07:00 GMT"
  set_now "2026-10-25 07:00"
  assert_eq day "$(active_theme)" "07:00 GMT"
}

test_invalid_slots_are_skipped() {
  write_schedule '{"slots":[{"at":"noon","theme":"bad"},{"at":"07:00","theme":"day"}]}'
  set_now "2026-10-28 12:00"
  assert_eq day "$(active_theme)" "the valid slot still works"
}

test_no_slots_means_nothing_active() {
  write_schedule '{"slots":[]}'
  set_now "2026-10-28 12:00"
  assert_eq "" "$(ts_active "$(ts_now)")" "empty schedule"
  rm "$HOME/.local/state/omarchy/settings/theme-schedule.json"
  assert_eq "" "$(ts_active "$(ts_now)")" "missing schedule"
}

test_next_switch() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-28 12:00"
  assert_eq "night $(epoch "2026-10-28 19:00")" "$(ts_next "$(ts_now)" | awk -F '\t' '{ print $4, $1 }')" "later today"
  set_now "2026-10-28 20:00"
  assert_eq "day $(epoch "2026-10-29 07:00")" "$(ts_next "$(ts_now)" | awk -F '\t' '{ print $4, $1 }')" "tomorrow morning"
}

test_occurrence_key_names_day_time_and_slot() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-28 12:00"
  assert_eq "2026-10-28T07:00 07:00->day" "$(ts_occurrence_key "$(ts_active "$(ts_now)")")" "key format"
}

test_polar_boundary_day_still_resolves() {
  # Tromsø's 2026-05-18 sunset is 00:32 on the 19th, and the 19th itself is
  # polar (fallback 07:00/19:00). At 00:40 the latest occurrence at or before
  # now is the 18th's sunset, so the night slot is active.
  export TZ=Europe/Oslo
  set_location 69.6492 18.9553 Tromsø
  write_schedule '{"slots":[{"at":"sunrise","theme":"day"},{"at":"sunset","theme":"night"}]}'
  set_now "2026-05-19 00:40"
  assert_eq night "$(active_theme)" "sunset spilling past midnight is still active"
  assert_eq "2026-05-18" "$(ts_active "$(ts_now)" | cut -f2)" "belongs to the 18th's occurrence"
  assert_eq "$(epoch "2026-05-19 07:00")" "$(ts_next "$(ts_now)" | cut -f1)" "next is the 19th's fallback sunrise"
}

run_tests
