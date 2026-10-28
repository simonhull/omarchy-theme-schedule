source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Prints "<rise> <set>" epochs, or "polar".
sun() {
  local lat=$1 lon=$2 day=$3 zone=$4 noon
  noon=$(TZ=$zone date -d "$day 12:00" +%s)
  gawk -v lat="$lat" -v lon="$lon" -v noon="$noon" -f "$OMARCHY_THEME_SCHEDULE_LIB/sun.awk"
}

check_sun() {
  local name=$1 lat=$2 lon=$3 day=$4 zone=$5 rise_utc=$6 set_utc=$7 rise set
  read -r rise set <<<"$(sun "$lat" "$lon" "$day" "$zone")"
  assert_within "$rise" "$(date -u -d "$rise_utc UTC" +%s)" 2 "$name sunrise $day"
  assert_within "$set" "$(date -u -d "$set_utc UTC" +%s)" 2 "$name sunset $day"
}

test_london_midsummer() {
  check_sun London 51.5072 -0.1276 2026-06-21 Europe/London "2026-06-21 03:43:04" "2026-06-21 20:21:36"
}

test_london_midwinter() {
  check_sun London 51.5072 -0.1276 2026-12-21 Europe/London "2026-12-21 08:03:37" "2026-12-21 15:53:31"
}

test_new_york_on_dst_start() {
  check_sun "New York" 40.7128 -74.0060 2026-03-08 America/New_York "2026-03-08 11:18:24" "2026-03-08 22:55:03"
}

test_new_york_on_dst_end() {
  check_sun "New York" 40.7128 -74.0060 2026-11-01 America/New_York "2026-11-01 11:26:36" "2026-11-01 21:52:35"
}

# Sydney's sunrise is the previous day in UTC: the day comes from local noon.
test_sydney_winter() {
  check_sun Sydney -33.8688 151.2093 2026-06-21 Australia/Sydney "2026-06-20 20:59:55" "2026-06-21 06:53:52"
}

# Fiji is UTC+12 and east of 178E: sunrise falls on the previous UTC day.
test_fiji_winter() {
  check_sun Fiji -18.1416 178.4419 2026-06-21 Pacific/Fiji "2026-06-20 18:36:41" "2026-06-21 05:39:12"
}

# Runs sun.awk with the given -v assignments; prints "<status>|<stdout>".
sun_raw() {
  local out status
  out=$(gawk "$@" -f "$OMARCHY_THEME_SCHEDULE_LIB/sun.awk" 2>/dev/null)
  status=$?
  printf '%s|%s' "$status" "$out"
}

test_no_variables_is_rejected() {
  assert_eq "2|" "$(sun_raw)" "no variables"
}

test_non_numeric_lat_is_rejected() {
  assert_eq "2|" "$(sun_raw -v lat=abc -v lon=0 -v noon=1782000000)" "lat=abc"
}

test_out_of_range_lat_is_rejected() {
  assert_eq "2|" "$(sun_raw -v lat=120 -v lon=0 -v noon=1782000000)" "lat=120"
}

test_missing_noon_is_rejected() {
  assert_eq "2|" "$(sun_raw -v lat=51.5 -v lon=-0.1)" "noon missing"
}

test_tromso_midnight_sun_is_polar() {
  assert_eq polar "$(sun 69.6492 18.9553 2026-06-21 Europe/Oslo)" "no sunset at midsummer"
}

test_tromso_polar_night_is_polar() {
  assert_eq polar "$(sun 69.6492 18.9553 2026-12-21 Europe/Oslo)" "no sunrise at midwinter"
}

run_tests
