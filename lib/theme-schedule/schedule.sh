# The logic behind omarchy-theme-schedule: reading the schedule and working
# out when each slot falls. Sourced, never run, and it changes nothing; it only
# answers "which slot is active now, and which comes next".
#
# A slot is {at, theme}. at is HH:MM, sunrise or sunset, optionally followed
# by an offset such as -30m or +1h. A slot recurs daily, and each day's
# instance of it is an occurrence.

TS_LIB=${OMARCHY_THEME_SCHEDULE_LIB:-/usr/share/omarchy-theme-schedule}
TS_STATE="$HOME/.local/state/omarchy"
TS_CONFIG="$TS_STATE/settings/theme-schedule.json"
TS_APPLIED="$TS_STATE/theme-schedule.applied"
TS_WEATHER="$TS_STATE/settings/weather.json"

# Sunrise and sunset when there is no location to work them out from, or on a
# polar day when the sun does not cross the horizon.
TS_FALLBACK_SUNRISE=07:00
TS_FALLBACK_SUNSET=19:00

ts_now() {
  echo "${OMARCHY_THEME_SCHEDULE_NOW:-$(date +%s)}"
}

# Prints "<base> <offset seconds>", or fails when at is not a schedule time.
ts_parse_at() {
  local base offset=0 amount

  [[ $1 =~ ^(sunrise|sunset|([01][0-9]|2[0-3]):[0-5][0-9])(([+-])([0-9]+)([mh]))?$ ]] || return 1
  base=${BASH_REMATCH[1]}

  if [[ -n ${BASH_REMATCH[3]} ]]; then
    amount=$((10#${BASH_REMATCH[5]}))
    [[ ${BASH_REMATCH[6]} == h ]] && amount=$((amount * 60))
    offset=$((amount * 60))
    [[ ${BASH_REMATCH[4]} == - ]] && offset=$((-offset))
  fi

  echo "$base $offset"
}

# The same normalisation omarchy-theme-set applies to the name it is given.
ts_normalize_theme() {
  sed -E 's/<[^>]+>//g' <<<"$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

ts_theme_installed() {
  [[ -n $1 && $1 != .* && $1 != */* ]] || return 1
  [[ -d ${OMARCHY_PATH:-/usr/share/omarchy}/themes/$1 || -d $HOME/.config/omarchy/themes/$1 ]]
}

ts_current_theme() {
  cat "$TS_STATE/current/theme.name" 2>/dev/null
}

# A local clock time on a day, as an epoch. A time a DST jump skips does not
# exist, so it counts that many minutes from midnight instead.
ts_clock_epoch() {
  local day=$1 time=$2 hours minutes

  date -d "$day $time" +%s 2>/dev/null && return 0

  hours=$((10#${time%:*}))
  minutes=$((10#${time#*:}))
  echo $(($(date -d "$day 00:00" +%s) + hours * 3600 + minutes * 60))
}

# The weather panel's location as "<lat> <lon>"; fails when none is set.
ts_location() {
  local lat lon

  read -r lat lon < <(jq -r '"\(.latitude) \(.longitude)"' "$TS_WEATHER" 2>/dev/null) || return 1
  [[ $lat =~ ^-?[0-9]+([.][0-9]+)?$ && $lon =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  echo "$lat $lon"
}

ts_location_name() {
  jq -r 'if (.name // "") != "" then .name else "\(.latitude), \(.longitude)" end' "$TS_WEATHER" 2>/dev/null
}

# Prints "<rise> <set>" epochs for a day, "polar", or "none" without a location.
ts_sun_times() {
  local location lat lon noon

  if ! location=$(ts_location); then
    echo none
    return
  fi

  read -r lat lon <<<"$location"
  noon=$(date -d "$1 12:00" +%s)
  gawk -v lat="$lat" -v lon="$lon" -v noon="$noon" -f "$TS_LIB/sun.awk"
}

# Why sunrise and sunset on a day are the fallback times: "no-location",
# "polar", or nothing when they are real.
ts_sun_fallback() {
  case $(ts_sun_times "$1") in
    none) echo no-location ;;
    polar) echo polar ;;
  esac
}

# The epoch of sunrise or sunset on a day.
ts_sun_event() {
  local day=$1 event=$2 times rise set

  times=$(ts_sun_times "$day")
  if [[ $times =~ ^[0-9]+\ [0-9]+$ ]]; then
    read -r rise set <<<"$times"
    if [[ $event == sunrise ]]; then echo "$rise"; else echo "$set"; fi
  elif [[ $event == sunrise ]]; then
    ts_clock_epoch "$day" "$TS_FALLBACK_SUNRISE"
  else
    ts_clock_epoch "$day" "$TS_FALLBACK_SUNSET"
  fi
}

# The epoch a slot's at falls on for a day; fails when at is not valid.
ts_resolve_slot() {
  local day=$1 parsed base offset epoch

  parsed=$(ts_parse_at "$2") || return 1
  read -r base offset <<<"$parsed"

  case $base in
    sunrise | sunset) epoch=$(ts_sun_event "$day" "$base") ;;
    *) epoch=$(ts_clock_epoch "$day" "$base") ;;
  esac

  echo $((epoch + offset))
}
