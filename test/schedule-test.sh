# shellcheck shell=bash
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
  for bad in 24:00 7:30 noon sunset-30 sunset+-1h Sunset "" "07:30 " 07:30+99999m; do
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

test_clock_epoch_in_a_dst_gap_lands_where_the_clock_resumes() {
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

ZONE_ROWS=(
  $'CA\t+5333-11328\tAmerica/Edmonton\tCST - AB, BC(E), NT(E), SK(W)'
  $'GB,GG,IM,JE\t+513030-0000731\tEurope/London'
  $'AU\t-3352+15113\tAustralia/Sydney\tNew South Wales'
)

test_timezone_location_parses_degrees_and_minutes() {
  export TZ=America/Edmonton
  set_zone_tab "${ZONE_ROWS[@]}"
  assert_eq "53.5500 -113.4667" "$(ts_location)" "Edmonton"
  assert_eq timezone "$(ts_location_source)" "source"
  assert_eq "America/Edmonton (from your timezone)" "$(ts_location_name)" "name"
}

test_timezone_location_parses_degrees_minutes_and_seconds() {
  export TZ=Europe/London
  set_zone_tab "${ZONE_ROWS[@]}"
  assert_eq "51.5083 -0.1253" "$(ts_location)" "London"
  export TZ=Australia/Sydney
  assert_eq "-33.8667 151.2167" "$(ts_location)" "Sydney, southern and eastern signs"
}

test_timezone_sunrise_comes_from_the_zone_location() {
  export TZ=America/Edmonton
  set_zone_tab "${ZONE_ROWS[@]}"
  assert_within "$(ts_sun_event 2026-10-28 sunrise)" "$(epoch "2026-10-28 08:25")" 5 "Edmonton sunrise"
  assert_eq "" "$(ts_sun_fallback 2026-10-28)" "not a fallback"
}

test_weather_location_beats_the_timezone() {
  export TZ=America/Edmonton
  set_zone_tab "${ZONE_ROWS[@]}"
  set_location 51.5072 -0.1276 London
  assert_eq "51.5072 -0.1276" "$(ts_location)" "weather wins"
  assert_eq weather "$(ts_location_source)" "source"
  assert_eq London "$(ts_location_name)" "name"
}

test_weather_file_without_coordinates_falls_to_the_timezone() {
  export TZ=America/Edmonton
  set_zone_tab "${ZONE_ROWS[@]}"
  printf '{"name":"Malibu"}\n' >"$HOME/.local/state/omarchy/settings/weather.json"
  assert_eq timezone "$(ts_location_source)" "source"
}

test_a_zone_missing_from_the_table_has_no_location() {
  export TZ=UTC
  set_zone_tab "${ZONE_ROWS[@]}"
  assert_eq no-location "$(ts_sun_fallback 2026-10-28)" "reason"
  assert_eq "" "$(ts_location_source)" "no source"
  assert_status 1 "ts_location fails" ts_location
}

test_zone_comes_from_etc_localtime_when_tz_is_unset_or_a_path() {
  local zone
  set_zone_tab "${ZONE_ROWS[@]}"
  [[ -e /usr/share/zoneinfo/Europe/London ]] || return 0
  unset TZ
  zone=$(readlink -f /etc/localtime)
  [[ $zone == */zoneinfo/* ]] || return 0
  assert_eq "${zone##*/zoneinfo/}" "$(ts_zone_name)" "from /etc/localtime"
  export TZ=/usr/share/zoneinfo/Europe/London
  assert_eq "${zone##*/zoneinfo/}" "$(ts_zone_name)" "a path in TZ is ignored"
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
  assert_eq "2026-10-27 2:19:00->night" "$(ts_occurrence_key "$(ts_active "$(ts_now)")")" "yesterday's occurrence"
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

test_occurrence_key_names_day_slot_and_theme() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-28 12:00"
  assert_eq "2026-10-28 1:07:00->day" "$(ts_occurrence_key "$(ts_active "$(ts_now)")")" "key format"
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

test_parse_at_reads_leading_zero_offsets_as_decimal() {
  assert_eq "08:30 540" "$(ts_parse_at 08:30+09m)" "09 is not octal"
}

test_resolve_slot_reads_leading_zero_times_as_decimal() {
  assert_eq "$(epoch "2026-10-28 09:08")" "$(ts_resolve_slot 2026-10-28 09:08)" "09:08 is not octal"
  assert_eq "$(epoch "2026-10-28 08:09")" "$(ts_resolve_slot 2026-10-28 08:09)" "08:09 is not octal"
}

test_clock_epoch_gap_keeps_leading_zero_minutes() {
  assert_eq "$(epoch "2026-03-29 02:08")" "$(ts_clock_epoch 2026-03-29 01:08)" "01:08 in the gap"
  assert_eq "$(epoch "2026-03-29 02:09")" "$(ts_clock_epoch 2026-03-29 01:09)" "01:09 in the gap"
}

test_clock_epoch_in_a_gap_at_midnight_zone() {
  export TZ=Africa/Cairo
  assert_eq "$(epoch "2026-04-24 01:30")" "$(ts_clock_epoch 2026-04-24 00:30)" "midnight does not exist in Cairo"
}

test_occurrences_in_a_zone_with_no_midnight() {
  export TZ=Africa/Cairo
  write_schedule "$DAY_NIGHT"
  set_now "2026-04-24 12:00"
  assert_eq day "$(active_theme)" "midday is day"
  assert_eq 2026-04-24 "$(ts_active "$(ts_now)" | cut -f2)" "slot day"
  local day
  while IFS= read -r day; do
    [[ $day =~ ^2026-04-2[345]$ ]] || fail "unexpected day field '$day'"
  done < <(ts_occurrences "$(ts_now)" | cut -f2)
  assert_eq 6 "$(ts_occurrences "$(ts_now)" | wc -l)" "three days of two slots"
}

test_occurrences_in_havana_and_beirut() {
  local zone day
  for zone in "America/Havana 2026-03-08" "Asia/Beirut 2026-03-29"; do
    export TZ=${zone% *}
    write_schedule "$DAY_NIGHT"
    set_now "${zone#* } 12:00"
    assert_eq 6 "$(ts_occurrences "$(ts_now)" | wc -l)" "$zone has six occurrences"
    assert_eq "${zone#* }" "$(ts_active "$(ts_now)" | cut -f2)" "$zone slot day"
  done
}

test_slot_numbers_follow_the_file_even_with_junk() {
  write_schedule '{"slots":[{"at":"07:00","theme":"a"},"x",{"at":"09:00","theme":"b"}]}'
  set_now "2026-10-28 10:00"
  assert_eq b "$(active_theme)" "valid slot after junk"
  assert_eq 3 "$(ts_active "$(ts_now)" | cut -f5)" "third entry in the file"
}

test_slots_object_instead_of_array_is_nothing() {
  write_schedule '{"slots":{"at":"07:00","theme":"a"}}'
  set_now "2026-10-28 10:00"
  assert_eq "" "$(ts_active "$(ts_now)")" "object slots"
}

test_slot_without_theme_is_skipped() {
  write_schedule '{"slots":[{"at":"07:00"},{"at":"06:00","theme":"a"},{"at":"08:00","theme":""},{"at":7,"theme":"z"}]}'
  set_now "2026-10-28 10:00"
  assert_eq a "$(active_theme)" "only the complete slot counts"
}

test_dst_spring_forward_neighbours_straddle_the_change() {
  export TZ=America/New_York
  write_schedule '{"slots":[{"at":"01:30","theme":"a"},{"at":"03:30","theme":"b"}]}'
  set_now "2026-03-08 03:15"
  assert_eq a "$(active_theme)" "03:15 EDT is still a"
  set_now "2026-03-08 03:30"
  assert_eq b "$(active_theme)" "03:30 EDT is b"
  local first second
  first=$(ts_resolve_slot 2026-03-08 01:30)
  second=$(ts_resolve_slot 2026-03-08 03:30)
  assert_eq 3600 "$((second - first))" "one real hour apart, not two"
}

test_dst_fall_back_neighbours_straddle_the_change() {
  write_schedule '{"slots":[{"at":"00:30","theme":"a"},{"at":"03:00","theme":"b"}]}'
  assert_eq 12600 "$(($(ts_resolve_slot 2026-10-25 03:00) - $(ts_resolve_slot 2026-10-25 00:30)))" "3.5 real hours"
}

test_sun_fallback_agrees_when_sun_awk_fails() {
  set_location 999 0 Nowhere
  assert_eq "$(epoch "2026-06-21 07:00")" "$(ts_sun_event 2026-06-21 sunrise)" "event falls back"
  assert_eq polar "$(ts_sun_fallback 2026-06-21)" "reason matches the fallback"
}

test_occurrence_days_are_calendar_neighbours_on_a_25_hour_day() {
  write_schedule "$DAY_NIGHT"
  set_now "2026-10-25 23:30"
  assert_eq "2026-10-24 2026-10-25 2026-10-26" "$(ts_occurrences "$(ts_now)" | cut -f2 | sort -u | tr '\n' ' ' | sed 's/ $//')" "yesterday and tomorrow by calendar"
  set_now "2026-10-25 00:15"
  assert_eq "2026-10-24 2026-10-25 2026-10-26" "$(ts_occurrences "$(ts_now)" | cut -f2 | sort -u | tr '\n' ' ' | sed 's/ $//')" "also just after midnight"
}

run_tests
