# Sunrise and sunset as UTC epoch seconds, from the sunrise equation with the
# -0.833 degree horizon published tables use (refraction plus the sun's
# radius, the same figure as the shell's Sun.js). Accurate to about a minute.
#
# Variables: lat and lon in degrees (north and east positive), and noon, the
# epoch of local noon on the day wanted. Prints "<rise> <set>", or "polar"
# when the sun does not cross the horizon that day.

function rad(d) { return d * PI / 180 }
function deg(r) { return r * 180 / PI }
function fmod(x, m) { return x - m * int(x / m) }
function round(x) { return x < 0 ? -int(-x + 0.5) : int(x + 0.5) }
function acos(x) { return atan2(sqrt(1 - x * x), x) }
function asin(x) { return atan2(x, sqrt(1 - x * x)) }

BEGIN {
  PI = atan2(0, -1)
  J2000 = 2451545.0
  UNIX_EPOCH_JD = 2440587.5

  # The day whose mean solar noon at this longitude is nearest the local noon
  # given, so places far east or west of their zone's meridian keep their day.
  n = round(noon / 86400 + UNIX_EPOCH_JD - J2000 + lon / 360)
  mean_noon = n - lon / 360

  anomaly = fmod(357.5291 + 0.98560028 * mean_noon, 360)
  centre = 1.9148 * sin(rad(anomaly)) + 0.0200 * sin(rad(2 * anomaly)) + 0.0003 * sin(rad(3 * anomaly))
  ecliptic = fmod(anomaly + centre + 180 + 102.9372, 360)
  transit = J2000 + mean_noon + 0.0053 * sin(rad(anomaly)) - 0.0069 * sin(rad(2 * ecliptic))
  declination = asin(sin(rad(ecliptic)) * sin(rad(23.4397)))

  cos_hour = (sin(rad(-0.833)) - sin(rad(lat)) * sin(declination)) / (cos(rad(lat)) * cos(declination))
  if (cos_hour < -1 || cos_hour > 1) {
    print "polar"
    exit
  }

  half_day = deg(acos(cos_hour)) / 360
  printf "%d %d\n", round((transit - half_day - UNIX_EPOCH_JD) * 86400), round((transit + half_day - UNIX_EPOCH_JD) * 86400)
}
