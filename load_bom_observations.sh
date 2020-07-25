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
# "-short:--long:variable:default:required:description:input:output:private"CSV
  "-d:--database:::true:SQLite database"
  "-l:--logfile:::false:Log file to record processing, defaults to \$database + .log"
  ":filename::::CSV file name; otherwise use stdin":true
)

source $(dirname "$0")/argrecord.sh

if [[ ! -n "${logfile}" ]] && [[ -n "${filename}" ]]; then
    logfile=$(basename ${filename})
    logfile="${logfile%.*}.log"
fi
echo -n "${COMMENTS}" > ${logfile}

INCOMMENTS=$(awk '/^#/{print};!/^#/{exit}' ${filename})
echo "${INCOMMENTS}" >> ${logfile}

sqlite3 ${database} -cmd '
CREATE TABLE IF NOT EXISTS observations(
"Station Number" INTEGER,
"Air temperature in Degrees C" REAL,
"Quality of air temperature" TEXT,
"Dew point temperature in Degrees C" REAL,
"Quality of dew point temperature" TEXT,
"Relative humidity in percentage %" INTEGER,
"Quality of relative humidity" TEXT,
"Wind speed measured in km/h" REAL,
"Quality of wind speed" TEXT,
"Wind direction measured in degrees" INTEGER,
"Quality of wind direction" TEXT,
"DateTime" TEXT
);' \
-cmd '.mode csv' \
-cmd '.import /dev/stdin observations'
