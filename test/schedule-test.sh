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

run_tests
