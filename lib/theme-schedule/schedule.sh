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

  [[ $1 =~ ^(sunrise|sunset|([01][0-9]|2[0-3]):[0-5][0-9])(([+-])([0-9]{1,4})([mh]))?$ ]] || return 1
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
# exist, so it lands where the clock resumes: the same minute an hour later,
# which covers every gap of an hour or less. Failing that (a longer gap, or no
# later hour on the day) it is counted from noon, which exists in every zone
# even where midnight does not.
ts_clock_epoch() {
  local day=$1 time=$2 hours minutes

  date -d "$day $time" +%s 2>/dev/null && return 0

  hours=$((10#${time%:*}))
  minutes=$((10#${time#*:}))
  if ((hours < 23)); then
    date -d "$day $(printf '%02d:%02d' $((hours + 1)) "$minutes")" +%s 2>/dev/null && return 0
  fi
  echo $(($(date -d "$day 12:00" +%s) + (hours * 60 + minutes - 720) * 60))
}

# The weather panel's coordinates as "<lat> <lon>"; fails when none are set.
ts_weather_location() {
  local lat lon

  read -r lat lon < <(jq -r '"\(.latitude) \(.longitude)"' "$TS_WEATHER" 2>/dev/null) || return 1
  [[ $lat =~ ^-?[0-9]+([.][0-9]+)?$ && $lon =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  echo "$lat $lon"
}

# The local timezone's name: $TZ when it is set and is not a path, otherwise
# what /etc/localtime points at, less everything up to "/zoneinfo/".
ts_zone_name() {
  local zone=${TZ:-} link

  zone=${zone#:}
  if [[ -n $zone && $zone != /* ]]; then
    echo "$zone"
    return
  fi

  link=$(readlink -f /etc/localtime 2>/dev/null) || return 1
  [[ $link == */zoneinfo/* ]] || return 1
  echo "${link##*/zoneinfo/}"
}

# The local timezone's coordinates as "<lat> <lon>", from zone1970.tab, whose
# second column is ISO 6709: +-DDMM+-DDDMM or +-DDMMSS+-DDDMMSS. Fails when the
# zone has no row (UTC, for one).
ts_zone_location() {
  local zone tab location

  zone=$(ts_zone_name) || return 1
  tab=${OMARCHY_THEME_SCHEDULE_ZONE_TAB:-/usr/share/zoneinfo/zone1970.tab}
  location=$(awk -F '\t' -v zone="$zone" '
    function degrees(part, deg_digits,   sign, digits) {
      sign = (substr(part, 1, 1) == "-") ? -1 : 1
      digits = substr(part, 2)
      return sign * (substr(digits, 1, deg_digits) + substr(digits, deg_digits + 1, 2) / 60 + (substr(digits, deg_digits + 3, 2) + 0) / 3600)
    }
    $0 !~ /^#/ && $3 == zone {
      split_at = match(substr($2, 2), /[+-]/)
      if (split_at == 0) exit
      lat = substr($2, 1, split_at)
      lon = substr($2, split_at + 1)
      printf "%.4f %.4f\n", degrees(lat, 2), degrees(lon, 3)
      exit
    }' "$tab" 2>/dev/null) || return 1
  [[ -n $location ]] || return 1
  echo "$location"
}

# Where the coordinates come from: "weather", "timezone", or nothing.
ts_location_source() {
  if ts_weather_location >/dev/null; then
    echo weather
  elif ts_zone_location >/dev/null; then
    echo timezone
  fi
}

# The location's coordinates as "<lat> <lon>": the weather panel's if it has
# any, else the timezone's. Fails when neither does.
ts_location() {
  ts_weather_location || ts_zone_location
}

ts_location_name() {
  case $(ts_location_source) in
    weather) jq -r 'if (.name // "") != "" then .name else "\(.latitude), \(.longitude)" end' "$TS_WEATHER" 2>/dev/null ;;
    timezone) echo "$(ts_zone_name) (from your timezone)" ;;
  esac
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
  local times
  times=$(ts_sun_times "$1")

  # Mirrors ts_sun_event: only "<rise> <set>" counts as real, so anything else
  # (including a sun.awk failure, which prints nothing) is a fallback day.
  if [[ $times == none ]]; then
    echo no-location
  elif [[ ! $times =~ ^[0-9]+\ [0-9]+$ ]]; then
    echo polar
  fi
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

# The schedule's slots, one "<number>\t<at>\t<theme>" line each, in file
# order. The number is the slot's 1-based place in the file, counting entries
# that are skipped as malformed, so "slot 3" always means the third entry.
ts_slots() {
  jq -r '.slots // [] | (if type == "array" then to_entries[] else empty end)
    | select(.value | type == "object" and (.at | type) == "string" and (.theme | type) == "string" and .theme != "")
    | [.key + 1, .value.at, .value.theme] | @tsv' "$TS_CONFIG" 2>/dev/null
}

# The entries ts_occurrences skips, one "<number>\t<reason>\t<at>" line each:
# "malformed" for an entry that is not an object with a string at and a
# non-empty theme, "bad-time" for one whose at is not a schedule time.
ts_skipped_slots() {
  local number kind at

  while IFS=$'\t' read -r number kind at; do
    if [[ $kind == bad ]]; then
      printf '%s\tmalformed\t\n' "$number"
    elif ! ts_parse_at "$at" >/dev/null; then
      printf '%s\tbad-time\t%s\n' "$number" "$at"
    fi
  done < <(jq -r '.slots // [] | (if type == "array" then to_entries[] else empty end)
    | if (.value | type == "object" and (.at | type) == "string" and (.theme | type) == "string" and .theme != "")
      then [.key + 1, "ok", .value.at] else [.key + 1, "bad", ""] end | @tsv' "$TS_CONFIG" 2>/dev/null)
}

# Every occurrence from yesterday to tomorrow as
# "<epoch>\t<day>\t<at>\t<theme>\t<slot number>", in time order. Yesterday is
# there so the hours before today's first slot belong to last night's; a
# later slot number sorts last on a tie, so it wins. Invalid slots are skipped.
# Neighbouring days are found from noon, which exists even in zones whose DST
# jump removes midnight, and with "ago"/"tomorrow" because "12:00 -1 day"
# would read -1 as a UTC offset.
ts_occurrences() {
  local today day at theme number epoch

  today=$(date -d "@$1" +%F)
  for day in "$(date -d "$today 12:00 1 day ago" +%F)" "$today" "$(date -d "$today 12:00 tomorrow" +%F)"; do
    while IFS=$'\t' read -r number at theme; do
      epoch=$(ts_resolve_slot "$day" "$at") || continue
      printf '%s\t%s\t%s\t%s\t%s\n' "$epoch" "$day" "$at" "$theme" "$number"
    done < <(ts_slots)
  done | sort -t $'\t' -k1,1n -k5,5n
}

# The occurrence active at an epoch: the latest one at or before it.
ts_active() {
  ts_occurrences "$1" | awk -F '\t' -v now="$1" '$1 <= now { line = $0 } END { if (line != "") print line }'
}

# The first occurrence after an epoch.
ts_next() {
  ts_occurrences "$1" | awk -F '\t' -v now="$1" '$1 > now { print; exit }'
}

# Names an occurrence as "<day> <slot number>:<at>-><theme>", the form
# recorded as applied. The day is the slot's own, so the same slot on another
# day differs. The resolved time is left out on purpose: it moves when the
# location does (weather set, timezone fallback), and that must not re-apply a
# slot over a theme picked by hand. Editing a slot changes its at, theme or
# position, so an edit still gets a new key and applies at once.
ts_occurrence_key() {
  local epoch day at theme number

  IFS=$'\t' read -r epoch day at theme number <<<"$1"
  printf '%s %s:%s->%s\n' "$day" "$number" "$at" "$theme"
}
