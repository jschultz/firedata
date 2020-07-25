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

help='Load BOM stations from CSV file.'
args=(
# "-short:--long:variable:default:required:description:input:output:private"
  "-d:--database:::true:SQLite database"
  ":filename:::true:CSV file name":true
)

source $(dirname "$0")/argrecord.sh

if [[ ! -n "${table}" ]]; then
    logfile=$(basename ${filename})
    logfile="${logfile%.*}.log"
fi
echo "${COMMENTS}" > ${logfile}

echo | sqlite3 ${database} << EOF
CREATE TABLE IF NOT EXISTS stations(
"st" TEXT,
"Station Number" INTEGER,
"Rainfall district code" TEXT,
"Station Name" TEXT,
"Month/Year site opened" TEXT,
"Month/Year site closed" TEXT,
"Latitude" REAL,
"Longitude" REAL,
"Method by which latitude/longitude was derived" TEXT,
"State" TEXT,
"Height of station" REAL,
"Height of barometer" REAL,
"WMO Index Number" INTEGER,
"First year" INTEGER,
"Last year" INTEGER,
"Percentage between first and last records" INTEGER,
"Percentage 'Y'" INTEGER,
"Percentage 'N'" INTEGER,
"Percentage 'W'" INTEGER,
"Percentage 'S'" INTEGER,
"Percentage 'I'" INTEGER,
"#" TEXT
);
.mode csv
.import ${filename} stations
UPDATE stations SET "Station Name" = trim("Station Name")
EOF