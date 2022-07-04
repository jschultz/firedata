#!/bin/bash
#
# Copyright 2020 Jonathan Schultz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
set -e

help='Load BOM station data from CSV file.'
args=(
# "-short:--long:variable:default:required:description:flags"
# "-short:--long:variable:default:required:description:input:output:private"CSV
  "-d:--database:::SQLite database:required"
  "-l:--logfile:::Log file to record processing, defaults to 'database' + .log"
  ":filename:::CSV file name:required,input"
  ":joinname:::Old CSV file name:required,input"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${logfile}" ]] && [[ -n "${filename}" ]]; then
    logfile=$(basename ${filename})
    logfile="${logfile%.*}.log"
fi
echo -n "${COMMENTS}" >> ${logfile}

csvFilter --jobs 1 --verbosity 1 \
  --prelude "joinfile = open(\"${joinname}\", \"r\")" \
            "joinreader = csv.DictReader(joinfile)" \
            "def humidity(station, year, month, day, hour, minute):" \
            "    try:" \
            "        joinrow = next(joinreader)" \
            "        assert(joinrow[\"Station Number\"] == station and" \
            "               joinrow[\"Year\"] == year and" \
            "               joinrow[\"Month\"] == month and" \
            "               joinrow[\"Day\"] == day and" \
            "               joinrow[\"Hour\"] == hour and" \
            "               joinrow[\"Minute in Local Standard Time\"] == minute)" \
            "        return joinrow[\"Relative humidity in percentage %\"]" \
            "    except StopIteration:" \
            "        return None" \
  --header  "Station Number" \
            "DateTime" \
            "Precipitation in mm" \
            "Air temperature in Degrees C" \
            "Dew point temperature in Degrees C" \
            "Relative humidity in percentage %" \
            "Wind speed measured in km/h" \
            "Wind direction measured in degrees" \
  --data    "[Station_Number]" \
            "[Year+'-'+Month+'-'+Day+' '+Hour+':'+Minute_in_Local_Standard_Time]" \
            "[Precipitation_in_mm]" \
            "[Air_temperature_in_Degrees_C]" \
            "[Dew_point_temperature_in_Degrees_C]" \
            "[humidity(Station_Number,Year,Month,Day,Hour,Minute_in_Local_Standard_Time)]" \
            "[Wind_speed_measured_in_km_h]" \
            "[Wind_direction_measured_in_degrees]" \
  --no-comments \
  --no-header \
  "${filename}" \
| sqlite3 ${database} -cmd '
CREATE TABLE IF NOT EXISTS observations(
"Station Number" INTEGER,
"DateTime" TEXT,
"Precipitation in mm" REAL,
"Air temperature in Degrees C" REAL,
"Dew point temperature in Degrees C" REAL,
"Relative humidity in percentage %" INTEGER,
"Wind speed measured in km/h" REAL,
"Wind direction measured in degrees" INTEGER,
PRIMARY KEY ("Station Number", "DateTime")
);' \
-cmd '.mode csv' \
-cmd '.import /dev/stdin observations'
